import Foundation
import Combine

// A simple container to track when a favorite was added.
private struct FavoriteMeta: Codable {
    let id: String
    let addedAt: Date
}

final class FavoritesStore: ObservableObject {
    // Publicly observable set of favorite IDs
    @Published private(set) var favorites: Set<String> = []
    
    // Internal metadata for ordering (date added)
    private var addedAt: [String: Date] = [:]
    
    // Cache of fetched products by ID to avoid re-downloading
    @Published private(set) var cachedProducts: [String: Product] = [:]
    
    private let idsKey = "FavoritesStore.ids"
    private let metaKey = "FavoritesStore.meta"
    private let cacheKey = "FavoritesStore.cachedProducts"
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        load()
        // Persist whenever favorites or cache change
        $favorites
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $cachedProducts
            .sink { [weak self] _ in self?.saveCache() }
            .store(in: &cancellables)
    }
    
    // MARK: - Public API
    
    func isFavorite(_ id: String) -> Bool {
        favorites.contains(id)
    }
    
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) {
            remove(id)
        } else {
            add(id)
        }
    }
    
    func add(_ id: String) {
        favorites.insert(id)
        if addedAt[id] == nil {
            addedAt[id] = Date()
        }
        save()
    }
    
    func remove(_ id: String) {
        favorites.remove(id)
        addedAt[id] = nil
        // Optionally keep cachedProducts[id] to show fast if re-added later; we’ll keep it.
        save()
    }
    
    func removeAll() {
        favorites.removeAll()
        addedAt.removeAll()
        // Keep cache; it’s harmless and can speed up future re-adds
        save()
    }
    
    // Ordered IDs by date added descending
    func orderedIDsByDateAddedDesc() -> [String] {
        favorites.sorted { lhs, rhs in
            let l = addedAt[lhs] ?? .distantPast
            let r = addedAt[rhs] ?? .distantPast
            return l > r
        }
    }
    
    // Merge fetched products into cache
    func updateCache(with products: [Product]) {
        var updated = cachedProducts
        for p in products {
            updated[p.id] = p
        }
        cachedProducts = updated
    }
    
    // MARK: - Persistence
    
    private func load() {
        let defaults = UserDefaults.standard
        
        // IDs
        if let data = defaults.data(forKey: idsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            favorites = decoded
        } else {
            favorites = []
        }
        
        // Metadata (addedAt)
        if let data = defaults.data(forKey: metaKey),
           let decoded = try? JSONDecoder().decode([FavoriteMeta].self, from: data) {
            var dict: [String: Date] = [:]
            for meta in decoded {
                dict[meta.id] = meta.addedAt
            }
            addedAt = dict
        } else {
            // Backfill missing timestamps with now for existing favorites
            let now = Date()
            addedAt = Dictionary(uniqueKeysWithValues: favorites.map { ($0, now) })
        }
        
        // Cache
        if let data = defaults.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([String: Product].self, from: data) {
            cachedProducts = decoded
        } else {
            cachedProducts = [:]
        }
    }
    
    private func save() {
        let defaults = UserDefaults.standard
        
        // IDs
        if let data = try? JSONEncoder().encode(favorites) {
            defaults.set(data, forKey: idsKey)
        }
        // Metadata
        let list = favorites.map { FavoriteMeta(id: $0, addedAt: addedAt[$0] ?? .distantPast) }
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: metaKey)
        }
    }
    
    private func saveCache() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(cachedProducts) {
            defaults.set(data, forKey: cacheKey)
        }
    }
}
