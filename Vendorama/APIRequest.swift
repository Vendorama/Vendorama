import Foundation

// Generic, fire-and-forget API request helper for lightweight GET endpoints.
// Automatically appends the API key via URLComponents.apiEndpoint.
struct APIRequest {
    // Core implementation: String id + optional extra query parameters.
    static func sendRequest(endpoint: String, id: String, extra: [String: String]? = nil) async {
        var items: [URLQueryItem] = [URLQueryItem(name: "id", value: id)]
        if let extra = extra {
            for (k, v) in extra {
                items.append(URLQueryItem(name: k, value: v))
            }
        }

        let components = URLComponents.apiEndpoint(endpoint, queryItems: items)
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return
            }
            // Response body is intentionally ignored; this is a best-effort ping.
        } catch {
            // Swallow errors (best-effort tracking).
        }
    }

    // Overload: any integer id
    static func sendRequest<T: BinaryInteger>(endpoint: String, id: T, extra: [String: String]? = nil) async {
        await sendRequest(endpoint: endpoint, id: String(id), extra: extra)
    }

    // Overload: any floating-point id
    static func sendRequest<T: BinaryFloatingPoint>(endpoint: String, id: T, extra: [String: String]? = nil) async {
        let number = Double(id)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6 // adjust if you need more precision
        formatter.numberStyle = .decimal
        let string = formatter.string(from: NSNumber(value: number)) ?? String(number)
        await sendRequest(endpoint: endpoint, id: string, extra: extra)
    }
}
