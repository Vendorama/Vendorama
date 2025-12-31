import SwiftUI
import SDWebImageSwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject var viewModel: SearchViewModel

    @State private var loadedFavorites: [Product] = []
    @State private var isLoading: Bool = false
    @AppStorage("favorites_layout") private var showGrid: Bool = false
    @AppStorage("favorites_vendors") private var showVendors: Bool = false
    @State private var confirmRemoveAll: Bool = false
    //@State private var showVendors: Bool = false
    @State private var sortVendorsByName: Bool = true
    @State private var vendorNames: [Int: String] = [:]

    // Minimal decoding for vendor endpoint
    private struct VendorDTO: Decodable { let name: String? }
    private struct VendorResponseDTO: Decodable { let vendor: [VendorDTO] }

    // Fetch vendor name for a given vendor id if unknown
    private func fetchVendorName(for vendorID: Int) async -> String? {
        let components = URLComponents.apiEndpoint(
            "vendor",
            queryItems: [
                URLQueryItem(name: "id", value: String(vendorID))
            ]
        )
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(VendorResponseDTO.self, from: data)
            return decoded.vendor.first?.name
        } catch {
            return nil
        }
    }

    // Dismiss the sheet from within this view
    @Environment(\.dismiss) private var dismissSheet

    // Build a stable string of IDs for dependency tracking and requests
    private var orderedIDs: [String] {
        favorites.orderedIDsByDateAddedDesc()
    }
    private var favoriteIDsCSV: String {
        orderedIDs.joined(separator: ",")
    }
    
    // Cache-first view models
    private var cachedOrderedProducts: [Product] {
        orderedIDs.compactMap { favorites.cachedProducts[$0] }
    }
    private var missingIDs: [String] {
        let cachedSet = Set(cachedOrderedProducts.map { $0.id })
        return orderedIDs.filter { !cachedSet.contains($0) }
    }

    var body: some View {
        Group {
            if favorites.favorites.isEmpty {
                emptyState
            } else if showVendors {
                vendorsListView
            } else if showGrid {
                gridView
            } else {
                listView
            }
        }
        .navigationBarItems(
            leading: HStack {
                toggleViewButton
                toggleVendorsButton
                toggleLayoutButton
                 
            },
            trailing: removeAllButton
        )
        .confirmationDialog(
            "Remove all favourites?",
            isPresented: $confirmRemoveAll,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) {
                favorites.removeAll()
                loadedFavorites = []
            }
            Button("Cancel", role: .cancel) { }
        }
        // On appearance or when IDs change, show cache immediately and fetch any missing
        .task(id: favoriteIDsCSV) {
            await loadFromCacheThenFetchMissing()
            await populateVendorNamesIfNeeded()
        }
        .refreshable {
            await fetchAllFavoritesReplacingCache()
        }
    }
    
    // MARK: - Subviews
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No favourites yet")
                .font(.headline)
            Text("Tap the heart on any product to save it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    private var toggleViewButton: some View {
        Button {
            withAnimation(.easeInOut) {
                if showVendors {
                    showVendors.toggle()
                }
                showGrid.toggle()
                
            }
        } label: {
            Image(systemName: showGrid ? "list.bullet" : "square.grid.2x2")
        }
        .accessibilityLabel(showGrid ? "Show list" : "Show grid")
    }
    
    private var toggleVendorsButton: some View {
        Button {
            withAnimation(.easeInOut) {
                showVendors.toggle()
                /*
                if !showGrid {
                    showGrid.toggle()
                }
                 */
            }
        } label: {
            Image(systemName: showVendors ? "storefront" : "storefront")
                .opacity(showVendors ? 1.0 : 0.2)
        }
        .accessibilityLabel(showVendors ? "Show products" : "Show vendors")
    }
    private var toggleLayoutButton: some View {
        
        Button {
            withAnimation(.easeInOut) { sortVendorsByName.toggle() }
        } label: {
            Image(systemName: sortVendorsByName ? "arrow.down" : "characters.lowercase")
        }
        .accessibilityLabel(sortVendorsByName ? "Sort vendors by ID" : "Sort vendors by name")
        .disabled(!showVendors)
        .opacity(showVendors ? 1.0 : 0.4)
    }
    
    private var removeAllButton: some View {
        Button(role: .destructive) {
            confirmRemoveAll = true
        } label: {
            Image(systemName: "trash")
        }
        .disabled(favorites.favorites.isEmpty)
        .accessibilityLabel("Remove all favourites")
    }
    
    private var listView: some View {
        let items = mergedProducts()
        return Group {
            if isLoading && items.isEmpty {
                VStack {
                    ProgressView()
                    Text("Loading favourites…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No details found for favourites")
                        .font(.headline)
                    Text("They may be unavailable. You can remove items or try again later.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else {
                List {
                    ForEach(items, id: \.id) { product in
                        NavigationLink(
                            destination:
                                ProductDetailView(
                                    product: product,
                                    viewModel: viewModel,
                                    onRequestDismissContainer: { dismissSheet() }
                                )
                        ) {
                            HStack(spacing: 12) {
                                if let url = apiURL(product.image) {
                                    WebImage(url: url)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipped()
                                        .cornerRadius(8)
                                } else {
                                    Rectangle()
                                        .fill(Color(.secondarySystemBackground))
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    if product.suburb != "" {
                                        Text(product.suburb)
                                            .font(.footnote)
                                            .lineLimit(1)
                                    }
                                    Text(product.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    PriceView(price: product.price, sale_price: product.sale_price)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        //.font(.footnote)
                                    Text(product.vendor_name)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                        .foregroundStyle(.secondary)
                                }
                                //Spacer()
                                
                                Button {
                                    favorites.toggleFavorite(product.id)
                                    removeFromLocal(product.id)
                                } label: {
                                    //Image(systemName: favorites.isFavorite(product.id) ? "heart.fill" : "heart")
                                    //.foregroundStyle(favorites.isFavorite(product.id) ? .purple : .secondary)
                                    Image(systemName: "heart.slash")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 16))
                                }
                                .buttonStyle(.plain)
                                .offset(x:-10)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
    
    private var gridView: some View {
        let items = mergedProducts()
        let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items, id: \.id) { product in
                    NavigationLink(
                        destination:
                            ProductDetailView(
                                product: product,
                                viewModel: viewModel,
                                onRequestDismissContainer: { dismissSheet() }
                            )
                    ) {
                        VStack(spacing: 6) {
                            
                            if let url = apiURL(product.image) {
                                WebImage(url: url)
                                    .resizable()
                                    .scaledToFit()
                                    .clipped()
                                    .frame(maxWidth: .infinity, maxHeight: 100)
                                    .background(Color(.systemBackground))
                                    .cornerRadius(8)
                                    .contentShape(Rectangle())
                            } else {
                                Rectangle()
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(height: 100)
                                    .cornerRadius(8)
                            }
                            // Grid shows image + price only
                            PriceView(price: product.price, sale_price: product.sale_price)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(8)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .overlay(
                            HStack {
                                Spacer()
                                VStack {
                                    Button {
                                        favorites.toggleFavorite(product.id)
                                        removeFromLocal(product.id)
                                    } label: {
                                        /*
                                         Image(systemName: favorites.isFavorite(product.id) ? "heart.fill" : "heart")
                                             .foregroundStyle(favorites.isFavorite(product.id) ? .purple : .secondary)
                                         
                                         Image(systemName: "trash")
                                             .foregroundStyle(.secondary)
                                         */
                                        Image(systemName: "heart.slash")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .padding(6)
                                            .background(.thickMaterial)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    Spacer()
                                }
                            }
                            .padding(6)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Vendors grouped view
    private struct VendorSection: Identifiable {
        let id: Int
        let displayName: String
        let products: [Product]
    }

    private var vendorsListView: some View {
        let sections = buildVendorSections()
        return List {
            ForEach(sections) { section in
                Section(header:
                    HStack {
                        Button {
                            dismissSheet()
                            DispatchQueue.main.async {
                                viewModel.searchVendor(to: String(section.id))
                            }
                        } label: {
                            Image("store")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.secondary)
                                .frame(height: 15)
                                .opacity(0.6)
                                .offset(x:1)
                            Text(section.displayName)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        // Unfavorite vendor directly
                        Button {
                            let key = "\(section.id).0"
                            favorites.toggleFavorite(key)
                        } label: {
                            Image(systemName: favorites.isFavorite("\(section.id).0") ? "heart.fill" : "heart")
                                .foregroundStyle(favorites.isFavorite("\(section.id).0") ? .purple : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(favorites.isFavorite("\(section.id).0") ? "Remove vendor from favourites" : "Add vendor to favourites")
                    }
                ) {
                    if section.products.isEmpty {
                        Text("No products")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(section.products, id: \.id) { product in
                            NavigationLink(
                                destination:
                                    ProductDetailView(
                                        product: product,
                                        viewModel: viewModel,
                                        onRequestDismissContainer: { dismissSheet() }
                                    )
                            ) {
                                HStack(spacing: 12) {
                                    if let url = apiURL(product.image) {
                                        WebImage(url: url)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 60, height: 60)
                                            .clipped()
                                            .cornerRadius(8)
                                    } else {
                                        Rectangle()
                                            .fill(Color(.secondarySystemBackground))
                                            .frame(width: 60, height: 60)
                                            .cornerRadius(8)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        if product.suburb != "" {
                                            Text(product.suburb)
                                                .font(.footnote)
                                                .lineLimit(1)
                                        }
                                        Text(product.name)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        PriceView(price: product.price, sale_price: product.sale_price)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(product.vendor_name)
                                            .font(.subheadline)
                                            .lineLimit(2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Button {
                                        favorites.toggleFavorite(product.id)
                                        removeFromLocal(product.id)
                                    } label: {
                                        Image(systemName: "heart.slash")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: -10)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func buildVendorSections() -> [VendorSection] {
        // Map vendorID -> [Product]
        var groups: [Int: [Product]] = [:]
        for product in mergedProducts() {
            if let vid = parseVendorID(from: product.id) {
                groups[vid, default: []].append(product)
            }
        }
        // Collect vendor-only favorites (IDs ending with .0)
        let vendorOnlyIDs: Set<Int> = Set(favorites.orderedIDsByDateAddedDesc().compactMap { id in
            if id.hasSuffix(".0"), let vid = parseVendorID(from: id) { return vid }
            return nil
        })
        // Union of vendors with products and vendor-only favorites
        let vendorIDsSet = Set(groups.keys).union(vendorOnlyIDs)
        // Build preliminary entries to sort by name if requested
        var prelim: [(id: Int, name: String, products: [Product])] = []
        for vid in vendorIDsSet {
            let products = groups[vid] ?? []
            let name = products.first?.vendor_name ?? vendorNames[vid] ?? "Vendor \(vid)"
            prelim.append((id: vid, name: name, products: products))
        }
        let sorted = prelim.sorted { lhs, rhs in
            if sortVendorsByName {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            } else {
                return lhs.id < rhs.id
            }
        }
        var sections: [VendorSection] = []
        for entry in sorted {
            sections.append(VendorSection(id: entry.id, displayName: entry.name, products: entry.products))
        }
        return sections
    }

    private func parseVendorID(from compositeID: String) -> Int? {
        // composite format: "vendorID.productID"
        let parts = compositeID.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first, let vid = Int(first) else { return nil }
        return vid
    }
    
    // MARK: - Data helpers
    
    private func mergedProducts() -> [Product] {
        var ordered: [Product] = []
        var seen = Set<String>()
        for id in orderedIDs {
            if let p = favorites.cachedProducts[id] {
                ordered.append(p)
                seen.insert(id)
            }
        }
        for p in loadedFavorites where !seen.contains(p.id) {
            ordered.append(p)
            seen.insert(p.id)
        }
        return ordered
    }
    
    private func removeFromLocal(_ id: String) {
        if !favorites.isFavorite(id) {
            loadedFavorites.removeAll { $0.id == id }
        }
    }
    
    // MARK: - Networking
    
    private func loadFromCacheThenFetchMissing() async {
        await MainActor.run {
            loadedFavorites = []
        }
        guard !missingIDs.isEmpty else { return }
        await fetch(ids: missingIDs, replaceAll: false)
    }
    
    private func fetchAllFavoritesReplacingCache() async {
        let ids = orderedIDs
        guard !ids.isEmpty else {
            await MainActor.run {
                loadedFavorites = []
            }
            return
        }
        await fetch(ids: ids, replaceAll: true)
    }
    
    private func fetch(ids: [String], replaceAll: Bool) async {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        
        let idsCSV = ids.joined(separator: ",")
        guard !idsCSV.isEmpty else { return }
        
        let components = URLComponents.apiEndpoint(
            "",
            queryItems: [
                URLQueryItem(name: "fv", value: idsCSV)
            ]
        )
        guard let url = components.url else { return }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            let decoded = try JSONDecoder().decode(ProductsResponse.self, from: data)
            let products = decoded.results
            //let vendor = decoded.vendor

            await MainActor.run {
                if replaceAll {
                    favorites.updateCache(with: products)
                    loadedFavorites = products
                } else {
                    favorites.updateCache(with: products)
                    var existing = loadedFavorites
                    var seen = Set(existing.map { $0.id })
                    for p in products where !seen.contains(p.id) {
                        existing.append(p)
                        seen.insert(p.id)
                    }
                    loadedFavorites = existing
                }
            }
        } catch {
            // Silent failure: keep current cache/UI
        }
    }
    
    // MARK: - Vendor names population for vendor-only favourites
    private func vendorOnlyFavoriteIDs() -> [Int] {
        favorites.orderedIDsByDateAddedDesc().compactMap { id in
            if id.hasSuffix(".0"), let vid = parseVendorID(from: id) { return vid }
            return nil
        }
    }

    @MainActor
    private func setVendorName(_ name: String?, for id: Int) {
        if let n = name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            vendorNames[id] = n
        }
    }

    private func populateVendorNamesIfNeeded() async {
        let vids = vendorOnlyFavoriteIDs()
        guard !vids.isEmpty else { return }
        // For each vendor id, if not already known from cached products, try to infer name or fetch from network
        for vid in vids {
            if vendorNames[vid] != nil { continue }
            // Try to infer from any cached/merged product for this vendor
            if let inferred = mergedProducts().first(where: { parseVendorID(from: $0.id) == vid })?.vendor_name,
               !inferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { setVendorName(inferred, for: vid) }
                continue
            }
            // Fetch from API vendor endpoint as fallback
            if let fetched = await fetchVendorName(for: vid),
               !fetched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { setVendorName(fetched, for: vid) }
            } else {
                // Leave placeholder; will show "Vendor <id>" until we know the name
                await MainActor.run { setVendorName(nil, for: vid) }
            }
        }
    }
}

