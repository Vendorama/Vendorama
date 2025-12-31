import SwiftUI

struct PrivacyView: View {
    var body: some View {
        InfoContentView(
            title: "Privacy Policy",
            contentId: 3,
            fallback: "For our privacy and security policies please visit our website at www.vendorama.co.nz/privacy",
            footerText: "For our terms and conditions please visit our website at www.vendorama.co.nz/terms",
            showContact: true,
            extraContent: nil
        )
    }
}
