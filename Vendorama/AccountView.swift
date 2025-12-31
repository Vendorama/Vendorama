import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss

    // If you already fetched profile, you can pass it in; otherwise leave defaults.
    @State private var email: String = ""
    @State private var password: String = ""

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var phone: String = ""
    @State private var address1: String = ""
    @State private var address2: String = ""
    @State private var city: String = ""
    @State private var postcode: String = ""

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    // Login presentation
    @State private var showLogin = false
    @State private var justLoggedIn = false

    // New: optional prefill passed from caller
    private let prefill: UserProfile?

    // Custom init to hydrate state from optional prefill
    init(prefill: UserProfile? = nil) {
        print("[AccountView] init with prefill:", String(describing: prefill))
        self.prefill = prefill
        // Use temporary State wrappers to assign initial values
        _email     = State(initialValue: prefill?.email ?? "")
        _firstName = State(initialValue: prefill?.first_name ?? "")
        _lastName  = State(initialValue: prefill?.last_name ?? "")
        _phone     = State(initialValue: prefill?.phone ?? "")
        _address1  = State(initialValue: prefill?.address1 ?? "")
        _address2  = State(initialValue: prefill?.address2 ?? "")
        _city      = State(initialValue: prefill?.city ?? "")
        _postcode  = State(initialValue: prefill?.postcode ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                if !isLoggedIn {
                    Section {
                        Button {
                            showLogin = true
                        } label: {
                            Text("(Please log in if you have an account)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        //.font(.footnote)
                    }
                    .listRowBackground(Color.clear)
                    .padding(0)
                    .padding(.bottom, 10)
                    .listSectionSpacing(0)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                Section(header: Text(isLoggedIn ? "My Account" : "Create Account").foregroundStyle(.secondary).textCase(nil)) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                    if !isLoggedIn {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                }
                if isLoggedIn {
                    Section {
                        Text("To reset password visit www.vendorama.co.nz/password")
                        
                            .frame(maxWidth: .infinity, alignment: .leading)
                            //.font(.footnote)
                    }
                    .listRowBackground(Color.clear)
                    .padding(0)
                    .padding(.bottom, 2)
                    .listSectionSpacing(0)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Section(header: Text("Profile").foregroundStyle(.secondary).textCase(nil)) {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("Address", text: $address1)
                        .textContentType(.streetAddressLine1)
                    TextField("Suburb", text: $address2)
                        .textContentType(.streetAddressLine2)
                    TextField("City", text: $city)
                        .textContentType(.addressCity)
                    TextField("Postcode", text: $postcode)
                        .keyboardType(.numbersAndPunctuation)
                        .textContentType(.postalCode)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            //.font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                if let successMessage {
                    Section {
                        Text(successMessage)
                            //.font(.footnote)
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 0) {
                    Button {
                        Task { await saveProfile() }
                    } label: {
                        if isSubmitting { ProgressView() } else {
                            HStack {
                                Spacer()
                                Text(isLoggedIn ? "Update Account" : "Create Account")
                                        .foregroundColor(.white)
                                        .bold()
                                        .font(.headline)
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(20)
                            .background(Color.blue)
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(0)
                    .disabled(isSubmitting || !saveEnabled)
                }
                .listRowBackground(Color.clear)
                .padding(0)
                .padding(.bottom, 20)
                
                if isLoggedIn {
                    Section {
                        Text("To edit your profile or delete your account please visit www.vendorama.co.nz/account\n\nFor privacy and security policies please visit www.vendorama.co.nz/privacy")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            //.font(.footnote)
                    }
                    .listRowBackground(Color.clear)
                    .padding(0)
                    .padding(.bottom, 10)
                    .listSectionSpacing(0)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
               
            }
            
            .formStyle(.grouped) // helps reduce the big top inset
            //.navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            /*
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
             */
            .task {
                // Refresh from server even if we had a prefill to ensure latest values
                if isLoggedIn {
                    try? await prefillFromServer()
                }
            }
            .sheet(isPresented: $showLogin, onDismiss: {
                // If user successfully logged in, prefill now
                if isLoggedIn {
                    Task { try? await prefillFromServer() }
                }
            }) {
                NavigationView {
                    LoginView()
                        .onDisappear {
                            // Flag that we likely just logged in (optional)
                            justLoggedIn = isLoggedIn
                        }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didLogin)) { _ in
                // After a successful login, refresh from server so fields reflect the new account
                Task { try? await prefillFromServer() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didLogout)) { _ in
                // Clear UI fields on logout to avoid showing stale data
                firstName = ""
                lastName = ""
                email = UserIdentityClient.storedEmail() ?? "" // likely empty after logout
                phone = ""
                address1 = ""
                address2 = ""
                city = ""
                postcode = ""
            }
        }
    }
/*
    private var isLoggedIn: Bool {
        if let uid = UserIdentityClient.userID(), uid > 0,
           let tok = UserIdentityClient.token(), !tok.isEmpty,
           let toe = UserIdentityClient.storedEmail(), !toe.isEmpty {
            return true
        }
        return false
    }
 */

    private var isLoggedIn: Bool {
    guard

        let email = UserIdentityClient.storedEmail(), !email.isEmpty,
        let uid = UserIdentityClient.userID(), uid > 0,
        let tok = UserIdentityClient.token(), !tok.isEmpty

    else { return false }

    return true

    }
    /*
     static func token() -> String? { UserIdentityStore.load()?.token }
     static func userID() -> Int? { UserIdentityStore.load()?.user_id }
     static func storedEmail() -> String? { UserIdentityStore.email() }
     static func storedFirstName() -> String? { UserIdentityStore.firstName() }
     */

    private var saveEnabled: Bool {
        // Allow saving if at least one field is filled or you can require email/password here if needed
        true
    }

    private func saveProfile() async {
        await setSubmitting(true)
        defer { Task { await setSubmitting(false) } }

        do {
            // If your server requires email/password in this endpoint, you can call login first or
            // extend updateProfile to include them. For now, updateProfile sends user_id/token.
            let profile = UserProfile(
                user_id: nil,
                first_name: firstName.isEmpty ? nil : firstName,
                last_name: lastName.isEmpty ? nil : lastName,
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone,
                address1: address1.isEmpty ? nil : address1,
                address2: address2.isEmpty ? nil : address2,
                city: city.isEmpty ? nil : city,
                postcode: postcode.isEmpty ? nil : postcode
            )
            try await UserIdentityClient.updateProfile(profile)
            await MainActor.run {
                successMessage = "Saved"
                // Optionally dismiss right away:
                // dismiss()
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func setSubmitting(_ v: Bool) async {
        isSubmitting = v
        if v { errorMessage = nil; successMessage = nil }
    }

    // Prefill from server if session exists
    private func prefillFromServer() async throws {
        let (_, profile) = try await UserIdentityClient.fetchAccount()
        if let p = profile {
            await MainActor.run {
                firstName = p.first_name ?? ""
                lastName = p.last_name ?? ""
                email = p.email ?? ""
                phone = p.phone ?? ""
                address1 = p.address1 ?? ""
                address2 = p.address2 ?? ""
                city = p.city ?? ""
                postcode = p.postcode ?? ""
            }
        }
    }
}
