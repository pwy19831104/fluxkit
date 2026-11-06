import AVFoundation
import MediaPlayer
import UIKit

/// Playback plumbing shared by the video and audio player: audio session, lock-screen
/// metadata, remote commands, and position tracking.
@MainActor
final class PlaybackSession {

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var interruptionObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var duration: Double = 0
    private var title = ""
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?
    /// Called when the player reaches the end (the queue uses this to auto-advance).
    var onEnded: (() -> Void)?
    /// Called with a ready-to-show message when the item cannot be played (corrupt/unsupported
    /// file, codec the device refuses). Without this the player showed a black screen forever.
    var onError: ((String) -> Void)?
    /// Lock-screen / headphone next & previous. The caller owns the queue, so it decides whether
    /// a step is possible and calls `setTrackSkip`.
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    private var itemStatusObservation: NSKeyValueObservation?
    private var failedToPlayObserver: NSObjectProtocol?

    var currentPosition: Double {
        guard let player else { return 0 }
        let value = CMTimeGetSeconds(player.currentTime())
        return value.isFinite ? max(0, value) : 0
    }

    var currentDuration: Double {
        guard let player, let item = player.currentItem else { return duration }
        let value = CMTimeGetSeconds(item.duration)
        return value.isFinite && value > 0 ? value : duration
    }

    var isPlaying: Bool { (player?.rate ?? 0) > 0 }

    // MARK: - Lifecycle

    func activate(player: AVPlayer, title: String, artworkURL: URL?, startAt: Double?, rate: Double) {
        self.player = player
        self.title = title
        self.artworkURL = artworkURL

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)

        installRemoteCommands()
        installObservers()
        installTimeObserver()
        observePlaybackFailure()

        if let startAt, startAt > 3 {
            let target = CMTime(seconds: startAt, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.defaultRate = Float(rate)
        player.play()

        loadDurationAndArtwork()
        updateNowPlaying()
    }

    func deactivate() {
        player?.pause()
        removeObservers()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        for (command, token) in commandTargets {
            command.removeTarget(token)
        }
        commandTargets.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        player = nil
    }

    func setRate(_ rate: Double) {
        guard let player else { return }
        player.defaultRate = Float(rate)
        if player.rate > 0 { player.rate = Float(rate) }
        updateNowPlaying()
    }

    // MARK: - Now Playing

    private func updateNowPlaying() {
        guard let player else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPosition,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: player.defaultRate,
        ]
        let total = currentDuration
        if total > 0 { info[MPMediaItemPropertyPlaybackDuration] = total }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Only the fields that actually change every second, instead of rebuilding the whole
    /// dictionary (title, duration, artwork) on each tick.
    private func refreshElapsedTime() {
        guard let player, var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentPosition
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Enables the lock-screen skip buttons; the caller knows the queue bounds.
    func setTrackSkip(enabledNext: Bool, enabledPrevious: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = enabledNext
        center.previousTrackCommand.isEnabled = enabledPrevious
    }

    private func loadDurationAndArtwork() {
        Task { [weak self] in
            guard let self, let player = self.player, let item = player.currentItem else { return }
            if let value = try? await item.asset.load(.duration) {
                let seconds = CMTimeGetSeconds(value)
                if seconds.isFinite, seconds > 0 { self.duration = seconds }
            }
            if let url = self.artworkURL,
               let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
            self.updateNowPlaying()
        }
    }

    // MARK: - Observers

    private func installTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshElapsedTime() }
        }
    }

    private func installObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                if type == .began {
                    player.pause()
                } else {
                    let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                        player.play()
                    }
                }
                self.updateNowPlaying()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                player.pause()
                if let onEnded = self.onEnded {
                    onEnded()
                } else {
                    player.seek(to: .zero)
                }
                self.updateNowPlaying()
            }
        }
    }

    private func observePlaybackFailure() {
        itemStatusObservation = player?.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.reportPlaybackFailure(item.error) }
        }
        failedToPlayObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: player?.currentItem, queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in self?.reportPlaybackFailure(error) }
        }
    }

    private func reportPlaybackFailure(_ error: Error?) {
        guard let onError else { return }
        guard let reason = error?.localizedDescription, !reason.isEmpty else {
            onError(L("This file can't be played.", "这个文件无法播放。"))
            return
        }
        onError(L("This file can't be played: \(reason)", "这个文件无法播放：\(reason)"))
    }

    private func removeObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        if let failedToPlayObserver {
            NotificationCenter.default.removeObserver(failedToPlayObserver)
        }
        failedToPlayObserver = nil
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    // MARK: - Remote commands

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        commandTargets.append((center.playCommand, center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.play() }
            return .success
        }))
        commandTargets.append((center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.pause() }
            return .success
        }))
        commandTargets.append((center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let player = self?.player else { return }
                if player.rate > 0 { player.pause() } else { player.play() }
            }
            return .success
        }))
        commandTargets.append((center.nextTrackCommand, center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNext?() }
            return .success
        }))
        commandTargets.append((center.previousTrackCommand, center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPrevious?() }
            return .success
        }))
        commandTargets.append((
            center.changePlaybackPositionCommand,
            center.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                Task { @MainActor in
                    self?.player?.seek(to: CMTime(seconds: event.positionTime, preferredTimescale: 600))
                }
                return .success
            }
        ))
    }
}
