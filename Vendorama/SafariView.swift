import SwiftUI
import SafariServices

public struct SafariView: UIViewControllerRepresentable {
    public let url: URL
    public var entersReaderIfAvailable: Bool
    public var dismissButtonStyle: SFSafariViewController.DismissButtonStyle

    public init(url: URL,
                entersReaderIfAvailable: Bool = false,
                dismissButtonStyle: SFSafariViewController.DismissButtonStyle = .done) {
        self.url = url
        self.entersReaderIfAvailable = entersReaderIfAvailable
        self.dismissButtonStyle = dismissButtonStyle
    }

    public func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = entersReaderIfAvailable
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.dismissButtonStyle = dismissButtonStyle
        return vc
    }

    public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No dynamic updates required for now.
    }
}
