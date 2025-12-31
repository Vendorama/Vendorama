import SwiftUI

struct InfoContentView: View {
    let title: String
    let contentId: Int
    let fallback: String
    let footerText: String?
    let showContact: Bool

    // Optional slot to inject extra content above the footer (e.g., a hero image)
    var extraContent: AnyView?

    @State private var showContactSheet = false
    @State private var contentText: String = " "

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(.init(contentText))
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()
                Spacer()
                Spacer()

                // Branding image (kept identical to your existing layout)
                HStack(spacing: 10) {
                    Image("vendorama")
                        .resizable()
                        .scaledToFit()
                        .padding(0)
                        .frame(maxWidth: .infinity, maxHeight: 100)
                        .frame(width: 170, height: 37, alignment: .center)
                        .offset(x: 78)
                }

                Text("""
Vendorama is 100% owned and operated by Vendorama limited (NZBN: 9429035722168).

If you have feedback or suggestions, I’d love to hear from you.
""")

                if showContact {
                    Button {
                        showContactSheet = true
                    } label: {
                        Label("Contact us or add your store here", systemImage: "envelope")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .tint(.accentColor)
                    .padding(.top, 4)
                }

                if let extra = extraContent {
                    extra
                }

                if let footer = footerText {
                    Section(header:
                        Text("\n\(footer)\n")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    ) { }
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showContactSheet) {
            NavigationView {
                ContactView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showContactSheet = false }
                        }
                    }
            }
        }
        .task {
            await loadContent(id: contentId)
        }
    }

    private struct ContentResponse: Decodable {
        let content: String
    }

    @MainActor
    private func loadContent(id: Int) async {
        let components = URLComponents.apiEndpoint(
            "content",
            queryItems: [
                URLQueryItem(name: "id", value: "\(id)"),
                URLQueryItem(name: "iu", value: "\(id)")
            ]
        )
        guard let url = components.url else {
            if id == contentId { contentText = fallback }
            return
        }
        print("content from \(url)")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                if id == contentId { contentText = fallback }
                return
            }
            let decoded = try JSONDecoder().decode(ContentResponse.self, from: data)
            let content = decoded.content
            if content.isEmpty {
                if id == contentId { contentText = fallback }
            } else {
                contentText = content
            }
        } catch {
            if id == contentId { contentText = fallback }
        }
    }
}
