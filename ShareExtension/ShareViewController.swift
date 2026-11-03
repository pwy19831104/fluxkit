import UIKit
import UniformTypeIdentifiers

/// Share-sheet entry point: pulls the first URL (or the first link inside shared text) out of
/// the extension item and drops it into the App Group inbox for the main app to pick up.
final class ShareViewController: UIViewController {

    private let card = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var savedLink: String?

    private let accent = UIColor(red: 0.41, green: 0.48, blue: 1.0, alpha: 1)
    private let cardBackground = UIColor(red: 0.075, green: 0.085, blue: 0.115, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        extractLink { [weak self] link in
            DispatchQueue.main.async {
                guard let self else { return }
                self.spinner.stopAnimating()
                if let link, SharedInbox.isAvailable {
                    SharedInbox.push(link)
                    self.savedLink = link
                    self.showSuccess(link: link)
                } else {
                    self.showFailure()
                }
            }
        }
    }

    // MARK: - UI

    private func buildUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = cardBackground
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        view.addSubview(card)

        let symbol = UIImage(systemName: "arrow.down.circle.fill",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold))
        iconView.image = symbol
        iconView.tintColor = accent
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Saving link…"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.text = "DownloadKit will start the download when you open the app."
        detailLabel.font = .systemFont(ofSize: 13.5, weight: .regular)
        detailLabel.textColor = UIColor(white: 0.68, alpha: 1)
        detailLabel.numberOfLines = 3
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        openButton.setTitle("Open DownloadKit", for: .normal)
        openButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        openButton.setTitleColor(.black, for: .normal)
        openButton.backgroundColor = accent
        openButton.layer.cornerRadius = 14
        openButton.layer.cornerCurve = .continuous
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.addTarget(self, action: #selector(openApp), for: .touchUpInside)
        openButton.isHidden = true

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        doneButton.setTitleColor(UIColor(white: 0.7, alpha: 1), for: .normal)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        doneButton.isHidden = true

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = accent

        [iconView, titleLabel, detailLabel, openButton, doneButton, spinner].forEach(card.addSubview)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            iconView.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            spinner.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            openButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 20),
            openButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            openButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            openButton.heightAnchor.constraint(equalToConstant: 50),

            doneButton.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 6),
            doneButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: 40),
            doneButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
    }

    private func showSuccess(link: String) {
        spinner.stopAnimating()
        titleLabel.text = "Link saved"
        let host = URL(string: link)?.host?.replacingOccurrences(of: "www.", with: "") ?? link
        detailLabel.text = "\(host)\nOpen DownloadKit to start the download."
        openButton.isHidden = false
        doneButton.isHidden = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func showFailure() {
        spinner.stopAnimating()
        titleLabel.text = "No link found"
        detailLabel.text = "Share a video link, or paste it directly in DownloadKit."
        doneButton.isHidden = false
    }

    // MARK: - Actions

    @objc private func openApp() {
        guard let url = URL(string: "downloadkit://") else { return }
        extensionContext?.open(url) { [weak self] opened in
            DispatchQueue.main.async {
                if !opened {
                    self?.detailLabel.text = "Link saved. Open DownloadKit from your Home Screen to start the download."
                    self?.openButton.isHidden = true
                } else {
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        }
    }

    @objc private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: - Extraction

    private func extractLink(completion: @escaping (String?) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion(nil)
            return
        }
        let providers = items.flatMap { $0.attachments ?? [] }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                var value: String?
                if let url = item as? URL {
                    value = url.absoluteString
                } else if let url = item as? NSURL {
                    value = url.absoluteString
                } else if let text = item as? String {
                    value = text
                }
                completion(value.flatMap(Self.normalized))
            }
            return
        }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                completion(Self.firstLink(in: item as? String))
            }
            return
        }

        if let text = items.first?.attributedContentText?.string {
            completion(Self.firstLink(in: text))
            return
        }

        completion(nil)
    }

    private static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return trimmed }
        return firstLink(in: trimmed) ?? trimmed
    }

    private static func firstLink(in text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url?.absoluteString
    }
}
