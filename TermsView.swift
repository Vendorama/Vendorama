import SwiftUI

struct TermsView: View {
    var body: some View {
        InfoContentView(
            title: "Terms",
            contentId: 5,
            fallback: " ",
            footerText: "For our privacy and security policies please visit our website at www.vendorama.co.nz/privacy",
            showContact: true,
            extraContent: nil
        )
    }
}
