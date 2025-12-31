import SwiftUI

struct FAQsView: View {
    var body: some View {
        InfoContentView(
            title: "FAQs",
            contentId: 2,
            fallback: " ",
            footerText: "For our privacy and security policies please visit our website at www.vendorama.co.nz/privacy\n\nFor our terms and conditions please visit our website at www.vendorama.co.nz/terms",
            showContact: true,
            extraContent: nil
        )
    }
}
