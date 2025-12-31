import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    // Success alert state
    @State private var showSuccessAlert = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Log in").foregroundStyle(.secondary).textCase(nil)) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            //.font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                
                HStack(spacing: 0) {
                    Button {
                        Task { await signIn() }
                    } label: {
                        if isSubmitting { ProgressView() } else {
                            HStack {
                                Spacer()
                                Text("Log In")
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
                }
                .listRowBackground(Color.clear)
                .padding(.bottom, 20)
                
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
/*
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        if isSubmitting { ProgressView() } else { Text("Log In") }
                    }
                    .disabled(isSubmitting || !formValid)
                }
 
 */
            }
            .navigationTitle("Log In")
            .formStyle(.grouped) // helps reduce the big top inset
            //.navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            
            /*
             HStack(spacing: 0) {
                 Button {
                     Task { await saveProfile() }
                 } label: {
                     if isSubmitting { ProgressView() } else {
                         HStack {
                             Spacer()
                             Text("Update Account")
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
             .padding(.bottom, 20)
             */
            /*
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
             */
        }
 
        // Brief success alert, then we dismiss the sheet programmatically
        .alert("You have been logged in.", isPresented: $showSuccessAlert) {
            // No buttons necessary; view will dismiss shortly after showing
        }
    }

    private var formValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }

    private func signIn() async {
        await setSubmitting(true)
        defer { Task { await setSubmitting(false) } }

        // Ensure any previous session/identity is cleared before a new login
        await MainActor.run {
            UserIdentityClient.logout()
        }

        do {
            // Perform login
            _ = try await UserIdentityClient.login(email: email, password: password)

            // Refresh identity and (optionally) profile so downstream views see the new user
            _ = await UserIdentityClient.fetchOrCreate()
            do {
                // Warm the account cache if available; ignore errors
                _ = try await UserIdentityClient.fetchAccount()
            } catch {
                // no-op: profile prefetch failure shouldn't block login flow
            }

            await MainActor.run {
                // Notify listeners and show success alert
                NotificationCenter.default.post(name: .didLogin, object: nil)
                showSuccessAlert = true
            }
            // Dismiss after a short delay so the alert is visible
            try? await Task.sleep(nanoseconds: 1_000_000_000) // ~1s
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func setSubmitting(_ v: Bool) async {
        isSubmitting = v
        if v { errorMessage = nil }
    }
}
