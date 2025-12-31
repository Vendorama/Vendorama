import SwiftUI
import MessageUI

struct AddURLView: View {
    // Persisted user details
    @AppStorage("contact_name") private var storedName: String = ""
    @AppStorage("contact_email") private var storedEmail: String = ""
    @AppStorage("contact_url") private var storedURL: String = ""

    // Form state
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var url: String = ""
    @State private var message: String = ""
    @State private var showingAlert: Bool = false
    @State private var subject: String = "Vendorama App Add Store Request"

    // Sending/alert state
    @State private var isSending: Bool = false
    @State private var alertTitle: String = "Thanks!"
    @State private var alertMessage: String = "Your message has been prepared."

    // Mail compose fallback
    @State private var showMailCompose: Bool = false
    @State private var mailComposeError: String?

    // Validation/limits
    private let messageLimit: Int = 500

    var body: some View {
        NavigationView {
            Form {
                
                Section(header:
                    Text("Enter the URL of your online store and we'll let you now when your store has been crawled by Vendobot. ")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, -10)
                        .textCase(nil)
                        .lineSpacing(5)
                ) {
                    
                }
                // First section with a minimal header to shrink top inset
                Section(header:
                    Text("Your Details")
                        //.font(.footnote)
                        .foregroundStyle(.secondary)
                        .textCase(nil) // keep original casing, avoids all-caps
                ) {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .autocapitalization(.words)
                        .onChange(of: name) { _, new in
                            storedName = new
                        }
                    TextField("URL", text: $url)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .onChange(of: url) { _, new in
                            storedURL = new
                        }

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .onChange(of: email) { _, new in
                            storedEmail = new
                        }

                    if !email.isEmpty && !isValidEmail(email) {
                        Text("Please enter a valid email address.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Invalid email")
                    }
                }
                
                Section(header:
                    Text("Message (optional)")
                        //.font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, -10)
                        .padding(.bottom, 0)
                        .textCase(nil)
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $message)
                            .frame(minHeight: 80)
                            .onChange(of: message) { _, newValue in
                                if newValue.count > messageLimit {
                                    message = String(newValue.prefix(messageLimit))
                                }
                            }

                        HStack {
                            Spacer()
                            Text("\(message.count)/\(messageLimit)")
                                .font(.caption)
                                .foregroundStyle(message.count >= messageLimit ? .red : .secondary)
                        }
                    }
                }

                Section {
                    Button(action: sendMessage) {
                        HStack {
                            if isSending {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Label(isSending ? "Sending..." : "Send", systemImage: "paperplane.fill")
                        }
                    }
                    .disabled(isSending || !formIsValid)
                }

                Section(header:
                    Text("Note that your online store must be located in New Zealand and meet the minimum requirements as detailed at www.vendorama.co.nz/bot\n\nFor our privacy and security policies please visit our website at www.vendorama.co.nz/privacy")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                ) {
                    
                }
                
            }
            .formStyle(.grouped) // helps reduce the big top inset
            .navigationTitle("Add Store")
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .alert(alertTitle, isPresented: $showingAlert) {
                if shouldOfferMailFallback {
                    Button("Compose Mail") {
                        showMailCompose = true
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showMailCompose) {
                MailComposeView(
                    subject: "Vendorama App Add Store Request",
                    recipients: ["sean@vendorama.co.nz"],
                    body: """
                          Name: \(name)
                          URL: \(url)
                          Email: \(email)

                          Message:
                          \(message)
                          """,
                    resultHandler: { result in
                        switch result {
                        case .success:
                            break
                        case .failure(let errorDescription):
                            mailComposeError = errorDescription
                            alertTitle = "Mail Not Sent"
                            alertMessage = errorDescription
                            showingAlert = true
                        }
                    }
                )
            }
            .onAppear {
                // Pre-fill from stored values
                if name.isEmpty { name = storedName }
                if url.isEmpty { url = storedURL }
                if email.isEmpty { email = storedEmail }
            }
        }
    }

    private var formIsValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidEmail(email)
        //&&
        //!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldOfferMailFallback: Bool {
        MFMailComposeViewController.canSendMail() && alertTitle == "Send Failed"
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func sendMessage() {
        guard !isSending else { return }
        isSending = true

        Task {
            do {
                let components = URLComponents.apiEndpoint(
                    "contact",
                    queryItems: [
                        URLQueryItem(name: "message", value: message),
                        URLQueryItem(name: "name", value: name),
                        URLQueryItem(name: "url", value: url),
                        URLQueryItem(name: "email", value: email),
                        URLQueryItem(name: "subject", value: subject)
                    ]
                )

                guard let url = components.url else {
                    throw URLError(.badURL)
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"

                let (data, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

                if (200...299).contains(statusCode) {
                    await MainActor.run {
                        alertTitle = "Thanks!"
                        alertMessage = "Your store will be added to Vendorama over then next few days."
                        showingAlert = true
                        message = ""
                        isSending = false
                    }
                } else {
                    let serverText = String(data: data, encoding: .utf8) ?? ""
                    throw NSError(
                        domain: "ContactAPI",
                        code: statusCode,
                        userInfo: [NSLocalizedDescriptionKey: serverText.isEmpty ? "Server returned status \(statusCode)." : serverText]
                    )
                }
            } catch {
                await MainActor.run {
                    alertTitle = "Send Failed"
                    alertMessage = error.localizedDescription
                    showingAlert = true
                    isSending = false
                }
            }
        }
    }
}

// MARK: - Mail Compose Wrapper

private struct MailComposeView: UIViewControllerRepresentable {
    enum ComposeResult {
        case success
        case failure(String)
    }

    let subject: String
    let recipients: [String]
    let body: String
    let resultHandler: (ComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setToRecipients(recipients)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(resultHandler: resultHandler)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let resultHandler: (ComposeResult) -> Void

        init(resultHandler: @escaping (ComposeResult) -> Void) {
            self.resultHandler = resultHandler
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            defer { controller.dismiss(animated: true) }
            if let error = error {
                resultHandler(.failure(error.localizedDescription))
                return
            }
            switch result {
            case .sent:
                resultHandler(.success)
            case .failed:
                resultHandler(.failure("Failed to send email."))
            default:
                resultHandler(.success)
            }
        }
    }
}
