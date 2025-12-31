import SwiftUI

@main
struct VendoramaSearchApp: App {
    @StateObject private var favorites = FavoritesStore()

    init() {
        let resolvedKey = (Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String) ?? ""
        print("API_KEY resolved length: \(resolvedKey.count)")
        if resolvedKey.isEmpty {
            print("WARNING: API_KEY is empty. Ensure Secrets.xcconfig is configured and Info.plist contains API_KEY = $(API_KEY).")
        }

        // Kick off user identity retrieval/creation
        Task {
            _ = await UserIdentityClient.fetchOrCreate()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(favorites)
        }
    }
}
