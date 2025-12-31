import Foundation

// Identity returned by your backend.
// Note: user_id is needed by the rest of the app.
struct UserIdentity: Codable {
    let user_id: Int
    let token: String
}

// Basic profile model matching your account JSON
struct UserProfile: Codable {
    var user_id: Int?
    var first_name: String?
    var last_name: String?
    var email: String?
    var phone: String?
    var address1: String?
    var address2: String?
    var city: String?
    var postcode: String?
}

// Persistence for identity + lightweight display fields (email/first_name)
enum UserIdentityStore {
    private static let identityKey = "UserIdentity.identity"
    private static let emailKey = "UserIdentity.email"
    private static let firstNameKey = "UserIdentity.firstName"

    // Identity persistence
    static func load() -> UserIdentity? {
        guard let data = UserDefaults.standard.data(forKey: identityKey) else { return nil }
        return try? JSONDecoder().decode(UserIdentity.self, from: data)
    }

    static func save(_ identity: UserIdentity) {
        if let data = try? JSONEncoder().encode(identity) {
            UserDefaults.standard.set(data, forKey: identityKey)
        }
    }

    // Clears identity and profile display data
    static func clear() {
        UserDefaults.standard.removeObject(forKey: identityKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
        UserDefaults.standard.removeObject(forKey: firstNameKey)
    }

    // Email persistence
    static func setEmail(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: emailKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: emailKey)
        }
    }

    static func email() -> String? {
        guard let v = UserDefaults.standard.string(forKey: emailKey), !v.isEmpty else { return nil }
        return v
    }

    // First name persistence (for greetings/UI)
    static func setFirstName(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: firstNameKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: firstNameKey)
        }
    }

    static func firstName() -> String? {
        guard let v = UserDefaults.standard.string(forKey: firstNameKey), !v.isEmpty else { return nil }
        return v
    }
}

// Networking client for identity/account
enum UserIdentityClient {
    // Fetch from cache or create on server if missing.
    // Bootstrap anonymous identity.
    static func fetchOrCreate() async -> UserIdentity? {
        if let cached = UserIdentityStore.load() {
            return cached
        }
        // Build endpoint: /user?id=&user_id=&token= (empty to request new)
        let components = URLComponents.apiEndpoint(
            "user",
            queryItems: [
                URLQueryItem(name: "id", value: ""),
                URLQueryItem(name: "user_id", value: ""),
                URLQueryItem(name: "token", value: "")
            ]
        )
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let identity = try JSONDecoder().decode(UserIdentity.self, from: data)
            UserIdentityStore.save(identity)
              print("[Identity] Saved new user_id=\(identity.user_id)")
            // Do not set email/first_name here; this is an anonymous identity
            return identity
        } catch {
            return nil
        }
    }

    // Convenience accessors
    static func token() -> String? {
        UserIdentityStore.load()?.token
    }

    static func userID() -> Int? {
        UserIdentityStore.load()?.user_id
    }

    static func storedEmail() -> String? {
        UserIdentityStore.email()
    }

    static func storedFirstName() -> String? {
        UserIdentityStore.firstName()
    }

    struct AuthError: LocalizedError, Decodable {
        let message: String
        var errorDescription: String? { message }

        // Allow decoding { "error": "..." } or { "message": "..." }
        enum CodingKeys: String, CodingKey { case error, message }
        init(message: String) { self.message = message }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let e = try? c.decode(String.self, forKey: .error) {
                message = e
            } else if let m = try? c.decode(String.self, forKey: .message) {
                message = m
            } else {
                message = "Authentication failed."
            }
        }
    }

    // POST /login with email/password and current anon identity
    static func login(email: String, password: String) async throws -> UserIdentity {
        var form: [String: String] = [
            "email": email,
            "password": password
        ]
        // Include current identity so backend can merge
        form["user_id"] = userID().map(String.init) ?? ""
        form["token"] = token() ?? ""

        let (data, http) = try await HTTP.postForm(endpoint: "login", form: form)
        guard (200...299).contains(http.statusCode) else {
            // Try to decode API error shape { "error": "..." } or { "message": "..." }
            if let apiErr = try? JSONDecoder().decode(AuthError.self, from: data) {
                throw apiErr
            }
            let msg = String(data: data, encoding: .utf8) ?? "Login failed with status \(http.statusCode)."
            throw AuthError(message: msg)
        }

        // Expected: { "user_id": Int, "token": String }
        let identity = try JSONDecoder().decode(UserIdentity.self, from: data)

        // Update stored identity (idempotent if same)
        UserIdentityStore.save(identity)

        // Mark signed-in by storing email used to authenticate
        UserIdentityStore.setEmail(email)

        // Notify listeners so UI can refresh
        NotificationCenter.default.post(name: .didLogin, object: nil)

        return identity
    }

    // POST /account to fetch account + refreshed token
    // Supports both preferred object and legacy string-encoded formats.
    static func fetchAccount() async throws -> (UserIdentity, UserProfile?) {
        var form: [String: String] = [:]
        form["user_id"] = userID().map(String.init) ?? ""
        form["token"] = token() ?? ""

        let (data, http) = try await HTTP.postForm(endpoint: "account", form: form)
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Account fetch failed with status \(http.statusCode)."
            throw AuthError(message: msg)
        }

        // Preferred nested-object response
        struct AccountResponseObject: Codable {
            let user_id: Int
            let token: String
            let account: UserProfile?
        }

        // Legacy string-encoded response
        struct AccountResponseString: Codable {
            let user_id: Int
            let token: String
            let account: String?
        }

        var identity: UserIdentity
        var profile: UserProfile? = nil

        if let obj = try? JSONDecoder().decode(AccountResponseObject.self, from: data) {
            identity = UserIdentity(user_id: obj.user_id, token: obj.token)
            profile = obj.account
        } else {
            let decoded = try JSONDecoder().decode(AccountResponseString.self, from: data)
            identity = UserIdentity(user_id: decoded.user_id, token: decoded.token)
            if let accountString = decoded.account, !accountString.isEmpty,
               let accountData = accountString.data(using: .utf8) {
                profile = try? JSONDecoder().decode(UserProfile.self, from: accountData)
            }
        }

        // Update stored identity if token/id changed
        UserIdentityStore.save(identity)

        // Keep local display values in sync if API returned them
        if let p = profile {
            if let e = p.email, !e.isEmpty, e != UserIdentityStore.email() {
                UserIdentityStore.setEmail(e)
            }
            if let fn = p.first_name, !fn.isEmpty, fn != UserIdentityStore.firstName() {
                UserIdentityStore.setFirstName(fn)
            }
        }

        return (identity, profile)
    }

    // Update profile fields (create/update on server); server may or may not return updated account
    static func updateProfile(_ profile: UserProfile) async throws {
        var form: [String: String] = [:]
        form["user_id"] = userID().map(String.init) ?? ""
        form["token"] = token() ?? ""

        if let v = profile.first_name { form["first_name"] = v }
        if let v = profile.last_name { form["last_name"] = v }
        if let v = profile.email { form["email"] = v }
        if let v = profile.phone { form["phone"] = v }
        if let v = profile.address1 { form["address1"] = v }
        if let v = profile.address2 { form["address2"] = v }
        if let v = profile.city { form["city"] = v }
        if let v = profile.postcode { form["postcode"] = v }

        let (data, http) = try await HTTP.postForm(endpoint: "account", form: form)
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Profile update failed with status \(http.statusCode)."
            throw AuthError(message: msg)
        }

        // Optimistically persist email/first name for UI
        if let e = profile.email, !e.isEmpty {
            UserIdentityStore.setEmail(e)
        }
        if let fn = profile.first_name, !fn.isEmpty {
            UserIdentityStore.setFirstName(fn)
        }
    }

    static func logout() {
        // Keep anonymous identity for tracking; clear only display/sign-in fields
        UserIdentityStore.setEmail(nil)
        UserIdentityStore.setFirstName(nil)

        // Notify listeners so UI can refresh
        NotificationCenter.default.post(name: .didLogout, object: nil)

        // If you want to fully reset identity as well, uncomment:
        // UserIdentityStore.clear()
    }
}

// Global login/logout notifications to drive UI toasts/updates
extension Notification.Name {
    static let didLogin = Notification.Name("didLogin")
    static let didLogout = Notification.Name("didLogout")
}
