import Foundation

enum HTTP {
    // POST application/x-www-form-urlencoded; api_key and token are appended via apiEndpoint
    static func postForm(endpoint: String, form: [String: String]) async throws -> (Data, HTTPURLResponse) {
        let components = URLComponents.apiEndpoint(endpoint)
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let body = form.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        // Debug logging
        print("[HTTP] POST \(endpoint) -> \(url.absoluteString)")
        print("[HTTP] Body: \(body)")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        // Debug response logging
        let snippet = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        print("[HTTP] Response \(endpoint) status=\(http.statusCode) body=\(snippet.prefix(500))")

        return (data, http)
    }
}
