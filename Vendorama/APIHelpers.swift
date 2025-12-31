import Foundation

enum APIKeyProvider {
    static var apiKey: String {
        if let key = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String, !key.isEmpty {
            return key
        }
        return ""
    }
}

enum APIConfig {
    static var appURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "API_URL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        return URL(string: "https://www.vendorama.co.nz/app/ios/1/")!
    }()
    static var baseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "BASE_URL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        return URL(string: "https://www.vendorama.co.nz/")!
    }()
}

extension URLComponents {
    mutating func appendAPIKey() {
        var items = self.queryItems ?? []
        items.append(URLQueryItem(name: "api_key", value: APIKeyProvider.apiKey))
        self.queryItems = items
    }

    // NEW: Append user token if we have one
    mutating func appendUserTokenIfAvailable() {
        if let token = UserIdentityClient.token(), !token.isEmpty {
            var items = self.queryItems ?? []
            items.append(URLQueryItem(name: "token", value: token))
            self.queryItems = items
        }
        if let userID = UserIdentityClient.userID(), userID != 0 {
            var items = self.queryItems ?? []
            items.append(URLQueryItem(name: "user_id", value: String(userID)))
            self.queryItems = items
        }
    }

    static func apiEndpoint(_ path: String = "", queryItems: [URLQueryItem] = []) -> URLComponents {
        var components = URLComponents(url: APIConfig.appURL, resolvingAgainstBaseURL: false)!

        if !path.isEmpty {
            let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let combinedPath = (components.path as NSString).appendingPathComponent(trimmed)
            components.path = combinedPath
        }

        components.queryItems = queryItems
        var withKey = components
        withKey.appendAPIKey()
        withKey.appendUserTokenIfAvailable() // ensure token is added
        return withKey
    }
}

// Global helper unchanged
func apiURL(_ relativePath: String) -> URL? {
    var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false)
    let combined = (components?.path as NSString? ?? "").appendingPathComponent(relativePath)
    components?.path = combined
    return components?.url
}

// Global utility: remove product totals in parentheses from category/location names.
// Example: "Clothing (335,117)" -> "Clothing"
func cleanCategoryName(_ raw: String?) -> String? {
    guard let name = raw, !name.isEmpty else { return raw }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if let parenIndex = trimmed.firstIndex(of: "(") {
        let prefix = trimmed[..<parenIndex]
        let cleaned = prefix.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        return cleaned.isEmpty ? nil : cleaned
    } else {
        let cleaned = trimmed.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        return cleaned.isEmpty ? nil : cleaned
    }
}

// Global helper: derive parent category ID from a (possibly subcategory) id.
// Returns nil if no parent can be inferred.
func computeParentCategoryID(from id: Int) -> Int? {
    // Explicit ranges (as per your BrowseView)
    if (1000...1499).contains(id) { return 100 }
    if (1500...1999).contains(id) { return 150 }
    if (2000...2499).contains(id) { return 200 }
    if (2500...2999).contains(id) { return 250 }
    if (3000...3499).contains(id) { return 300 }
    if (3500...3999).contains(id) { return 350 }
    if (4000...4499).contains(id) { return 400 }
    if (4500...4999).contains(id) { return 450 }
    if (5000...5499).contains(id) { return 500 }
    if (5500...5999).contains(id) { return 550 }
    if (6000...6499).contains(id) { return 600 }
    if (9000...9999).contains(id) { return 900 }

    // General rule fallback (keeps previous behavior)
    if id >= 1000 {
        return (id / 1000) * 100
    }

    // Treat top-level categories as their own parent
    if id > 0 {
        return id
    }
    return nil
}
