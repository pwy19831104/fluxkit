import Foundation
import Network
import Observation

extension Notification.Name {
    /// Posted whenever the network path changes (Wi-Fi ↔ cellular, offline, …).
    static let fluxKitNetworkChanged = Notification.Name("fluxkit.network.changed")
}

@MainActor
@Observable
final class NetworkMonitor {

    static let shared = NetworkMonitor()

    private(set) var isConnected = true
    private(set) var isOnWiFi = true
    private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "fluxkit.network.monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                self.isOnWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                self.isExpensive = path.isExpensive
                NotificationCenter.default.post(name: .fluxKitNetworkChanged, object: nil)
            }
        }
        monitor.start(queue: queue)
    }

    /// True when a download is allowed to start.
    func allowsDownloads(wifiOnly: Bool) -> Bool {
        guard isConnected else { return false }
        return !wifiOnly || isOnWiFi
    }
}
