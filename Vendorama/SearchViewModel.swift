import SwiftUI
import Foundation

struct ProductsResponse: Decodable {
    let results: [Product]
    let total_rs: Int
    let page: Int
    let per_page: Int
    let vendor: [Vendor]? // Optional: may be absent on non-vendor searches
}

class SearchViewModel: ObservableObject {
    
    // Centralized list of non-user search terms (lowercased)
    static let excludedQueries: Set<String> = [
        "new",
        "trending",
        "similar",
        "new",
        "new arrivals",
        "for you"
    ]

    @Published var products: [Product] = []
    @Published var vendor: [Vendor] = []
    @Published private var historyStack: [HistoryEntry] = []
    
    @Published var query: String = ""
    @Published var isLoading: Bool = false
    @Published var hasMorePages: Bool = true
    @Published var searchID = UUID()
    @Published var searchType: String = "search"
    @Published var lastQuery: String = ""
    @Published var lastSearchType: String = "search"
    @Published var totalResults: Int? = nil
    @Published var hasSearched: Bool = false
    @Published var restrictedOnly: Bool = false

    @Published var withinVendorSearch: Bool = false

    @Published var currentPage = 1
    private var isFetching = false
    
    private var currentRelatedID: String?
    private var currentVendorID: String?
    
    // Vendor category (used in vendor search flow)
    @Published var selectedCategoryID: Int?

    // Global category filters (top-level and optional subcategory)
    @Published var selectedTopCategoryID: Int?
    @Published var selectedSubcategoryID: Int?
    @Published var selectedSubcategoryIDs: Set<Int> = []

    // Human-readable names for current category filters
    @Published var selectedTopCategoryName: String?
    @Published var selectedSubcategoryName: String?

    // In-memory categories cache (session-scoped)
    @Published var cachedTopCategories: [CategoryItem] = []
    var cachedSubcategoriesByParent: [Int: [CategoryItem]] = [:]

    // Vendor/location filters
    @Published var selectedLocationID: Int?
    @Published var selectedTopLocationID: Int?
    @Published var selectedSubLocationID: Int?
    @Published var selectedSubLocationIDs: Set<Int> = []
    @Published var selectedTopLocationName: String?
    @Published var selectedSubLocationName: String?

    @Published var priceFrom: Int?
    @Published var priceTo: Int?
    @Published var onSale: Bool = false
    @Published var priceFromRaw: String?
    @Published var priceToRaw: String?

    private let debugLogging: Bool = true
    private var seenIDs = Set<String>()

    private let session: URLSession = {
        let cache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()

    private struct HistoryEntry {
        let products: [Product]
        let query: String
        let searchType: String
        let priceFrom: Int?
        let priceTo: Int?
        let onSale: Bool
        let withinVendorSearch: Bool
        
        let selectedCategoryID: Int?
        let selectedTopCategoryID: Int?
        let selectedSubcategoryID: Int?
        let selectedSubcategoryIDs: Set<Int>
        let selectedTopCategoryName: String?
        let selectedSubcategoryName: String?
        
        let selectedLocationID: Int?
        let selectedTopLocationID: Int?
        let selectedSubLocationID: Int?
        let selectedSubLocationIDs: Set<Int>
        let selectedTopLocationName: String?
        let selectedSubLocationName: String?
        
        
        let totalResults: Int?
        let currentRelatedID: String?
        let currentVendorID: String?
        let seenIDs: Set<String>
    }

    var activeFiltersCount: Int {
        var count = 0
        if priceFrom != nil || priceTo != nil { count += 1 }
        if onSale == true { count += 1 }
        if selectedTopCategoryID != nil || selectedSubcategoryID != nil || !selectedSubcategoryIDs.isEmpty {
            count += 1
        }
        if selectedTopLocationID != nil || selectedSubLocationID != nil || !selectedSubLocationIDs.isEmpty {
            count += 1
        }
        return count
    }
    
    // Centralized full reset for a brand new search context
    func resetFilters() {
        // Text/modes/context
        query = ""
        lastQuery = ""
        searchType = "search"
        withinVendorSearch = false
        currentRelatedID = nil
        currentVendorID = nil
        selectedCategoryID = nil // vendor category
        
        // All filters
        priceFrom = nil
        priceTo = nil
        onSale = false
        restrictedOnly = false
        
        // Categories
        selectedTopCategoryID = nil
        selectedTopCategoryName = nil
        selectedSubcategoryID = nil
        selectedSubcategoryName = nil
        selectedSubcategoryIDs = []
        
        // Locations
        selectedTopLocationID = nil
        selectedTopLocationName = nil
        selectedSubLocationID = nil
        selectedSubLocationName = nil
        selectedSubLocationIDs = []
        
        // Results/paging
        products = []
        vendor = []
        totalResults = nil
        hasSearched = false
        hasMorePages = true
        currentPage = 1
        seenIDs.removeAll()
    }
    
    func search(reset: Bool = true, thisType: String = "search") {
        if !products.isEmpty { pushHistory() }
        lastQuery = query
        lastSearchType = searchType
        guard !isFetching else { return }

        products = []
        vendor = []
        currentPage = 1
        hasMorePages = true
        searchID = UUID()
        searchType = thisType
        currentRelatedID = nil
        currentVendorID = nil
        totalResults = nil
        seenIDs.removeAll()
        if thisType != "vendor" {
            selectedCategoryID = nil
            withinVendorSearch = false
        }
        fetchPage()
    }
    
    func searchRelated(to product: Product) {
        if !products.isEmpty { pushHistory() }
        lastQuery = query
        lastSearchType = searchType
        products = []
        vendor = []
        isLoading = true
        hasMorePages = true
        currentPage = 1
        searchType = "related"
        currentRelatedID = product.id
        currentVendorID = nil
        totalResults = nil
        selectedCategoryID = nil
        selectedLocationID = nil
        withinVendorSearch = false
        seenIDs.removeAll()
        fetchPage(relatedTo: product.id)
    }
    
    func searchVendor(to vendorID: String) {
        if !products.isEmpty { pushHistory() }
        lastQuery = query
        lastSearchType = searchType
        products = []
        vendor = []
        isLoading = true
        hasMorePages = true
        currentPage = 1
        searchType = "vendor"
        currentVendorID = vendorID
        currentRelatedID = nil
        totalResults = nil
        selectedCategoryID = nil
        seenIDs.removeAll()
        fetchPage(vendorID: vendorID)
    }
    
    func loadNextPageIfNeeded(currentItem item: Product?) {
        guard let item = item else { return }
        let thresholdIndex = products.index(products.endIndex, offsetBy: -6, limitedBy: products.startIndex) ?? products.startIndex
        if let itemIndex = products.firstIndex(where: { $0.id == item.id }), itemIndex >= thresholdIndex {
            switch searchType {
            case "related": loadNextPage(relatedTo: currentRelatedID)
            case "vendor":  loadNextPage(vendorID: currentVendorID)
            default:        loadNextPage()
            }
        }
    }
    
    func loadNextPage(relatedTo relatedID: String? = nil, vendorID: String? = nil) {
        guard hasMorePages, !isFetching else { return }
        currentPage += 1
        fetchPage(relatedTo: relatedID ?? currentRelatedID, vendorID: vendorID ?? currentVendorID, append: true)
    }
    
    func refreshFirstPage() {
        guard !isFetching else { return }
        print("[SearchVM] refreshFirstPage pf=\(String(describing: priceFrom)) pt=\(String(describing: priceTo)) restricted=\(restrictedOnly) topCat=\(String(describing: selectedTopCategoryID)) subCatSingle=\(String(describing: selectedSubcategoryID)) subCatMulti=\(selectedSubcategoryIDs)")
        hasMorePages = true
        currentPage = 1
        totalResults = nil
        products = []
        if searchType != "vendor" { vendor = [] }
        seenIDs.removeAll()
        fetchPage(relatedTo: currentRelatedID, vendorID: currentVendorID, append: false, forceRefresh: true)
    }
    
    func refreshCurrentPage() {
        guard !isFetching else { return }
        fetchPage(relatedTo: currentRelatedID, vendorID: currentVendorID, append: false, forceRefresh: true)
    }
    
    func refresh() {
        refreshFirstPage()
    }
    
    private func fetchPage(relatedTo relatedID: String? = nil, vendorID: String? = nil, append: Bool = false, forceRefresh: Bool = false) {
        guard !isFetching else { return }
        isFetching = true
        isLoading = true
        
        print("[SearchVM] Current filters pf=\(String(describing: priceFrom)) pt=\(String(describing: priceTo)) topCat=\(String(describing: selectedTopCategoryID)) subCatSingle=\(String(describing: selectedSubcategoryID)) subCatMulti=\(selectedSubcategoryIDs)")

        var queryItems: [URLQueryItem] = []
        
        let normalizedVQ: String? = {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !Self.excludedQueries.contains(trimmed.lowercased()) else { return nil }
            return String(trimmed.lowercased().prefix(100))
        }()
        
        let realVQ: String? = {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.lowercased().prefix(100))
        }()
        
        switch searchType {
        case "related":
            guard let vsValue = relatedID else {
                isFetching = false
                isLoading = false
                if debugLogging { print("[SearchVM] Missing relatedID for related fetch. Aborting page \(currentPage).") }
                return
            }
            queryItems.append(URLQueryItem(name: "vs", value: vsValue))
        case "vendor":
            guard let vid = vendorID else {
                isFetching = false
                isLoading = false
                if debugLogging { print("[SearchVM] Missing vendorID for vendor fetch. Aborting page \(currentPage).") }
                return
            }
            queryItems.append(URLQueryItem(name: "vu", value: vid))
            if let ci = selectedCategoryID {
                queryItems.append(URLQueryItem(name: "ci", value: String(ci)))
            }
            if let nm = selectedLocationID {
                queryItems.append(URLQueryItem(name: "nm", value: String(nm)))
            }
            if withinVendorSearch, let vq = normalizedVQ {
                queryItems.append(URLQueryItem(name: "vq", value: vq))
            }
        default:
            if let vq = normalizedVQ {
                queryItems.append(URLQueryItem(name: "vq", value: vq))
            } else if let realvq = realVQ, !realvq.isEmpty, activeFiltersCount == 0 {
                // trending, new
                queryItems.append(URLQueryItem(name: "vq", value: realvq))
            }
            
            if !selectedSubcategoryIDs.isEmpty {
                let csv = selectedSubcategoryIDs.sorted().map(String.init).joined(separator: ",")
                queryItems.append(URLQueryItem(name: "vc", value: csv))
            } else if let subID = selectedSubcategoryID {
                queryItems.append(URLQueryItem(name: "vc", value: String(subID)))
            } else if let topID = selectedTopCategoryID {
                queryItems.append(URLQueryItem(name: "vc", value: String(topID)))
            }
            
            if !selectedSubLocationIDs.isEmpty {
                let csv = selectedSubLocationIDs.sorted().map(String.init).joined(separator: ",")
                queryItems.append(URLQueryItem(name: "vl", value: csv))
            } else if let subID = selectedSubLocationID {
                queryItems.append(URLQueryItem(name: "vl", value: String(subID)))
            } else if let topID = selectedTopLocationID {
                queryItems.append(URLQueryItem(name: "vl", value: String(topID)))
            }
        }
        
        if let pf = priceFrom {
            queryItems.append(URLQueryItem(name: "price_from", value: String(pf)))
        }
        if let pt = priceTo {
            queryItems.append(URLQueryItem(name: "price_to", value: String(pt)))
        }
        
        if onSale {
            queryItems.append(URLQueryItem(name: "onsale", value: "1"))
        }
        
        if restrictedOnly {
            queryItems.append(URLQueryItem(name: "restricted", value: "1"))
        }
        if currentPage > 1 {
            queryItems.append(URLQueryItem(name: "page", value: String(currentPage)))
        }
        
        print("[SearchVM] QueryItems: " + queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"))
        
        let components = URLComponents.apiEndpoint("", queryItems: queryItems)
        
        guard let url = components.url else {
            isFetching = false
            isLoading = false
            print("[SearchVM] Error building URL for page \(currentPage).")
            return
        }
        //print(url.absoluteString)
        if debugLogging {
            print("[SearchVM] Fetching page \(currentPage) [\(searchType)] -> \(url.absoluteString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        
        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            if self.debugLogging {
                if let status = status {
                    print("[SearchVM] HTTP status: \(status) for page \(self.currentPage)")
                } else {
                    print("[SearchVM] No HTTP status for page \(self.currentPage)")
                }
            }
            
            DispatchQueue.main.async {
                self.isFetching = false
                self.isLoading = false
                self.hasSearched = true
            }
            if let error = error {
                print("[SearchVM] Network error: \(error.localizedDescription)")
                return
            }
            guard let data = data else {
                print("[SearchVM] No data received.")
                return
            }
            do {
                let response = try JSONDecoder().decode(ProductsResponse.self, from: data)
                let newProducts = response.results
                let newVendor = response.vendor ?? []
                if self.debugLogging {
                    print("[SearchVM] Decoded \(newProducts.count) items on page \(self.currentPage). Append: \(append)")
                    print("[SearchVM] Total results: \(response.total_rs)")
                    //if self.searchType == "vendor" {
                        print("[SearchVM] Vendor payload count: \(newVendor.count)")
                    //}
                }
                DispatchQueue.main.async {
                    self.totalResults = response.total_rs

                    let filtered: [Product] = newProducts.filter { p in
                        if self.seenIDs.contains(p.id) {
                            return false
                        } else {
                            self.seenIDs.insert(p.id)
                            return true
                        }
                    }
                    
                    if append {
                        self.products.append(contentsOf: filtered)
                    } else {
                        self.products = filtered
                    }
                    /* */
                    // If this was a normal search but the API returned vendor details (exact match),
                    // switch to vendor mode and display the vendor header/details.
                    if self.searchType == "search", newVendor.count == 1 {
                        self.searchType = "vendor"
                        self.query = ""
                        self.currentVendorID = newVendor.first?.vendor_id.map(String.init)
                        
                    }
                    
                    if self.searchType == "vendor" {
                        if append {
                            if self.vendor.isEmpty {
                                self.vendor = newVendor
                            } else {
                                self.vendor.append(contentsOf: newVendor)
                            }
                        } else {
                            self.vendor = newVendor
                        }
                    } else {
                        self.vendor = []
                    }
                    
                    if self.products.count >= response.total_rs || filtered.isEmpty {
                        self.hasMorePages = false
                        if self.debugLogging {
                            print("[SearchVM] No more pages after page \(self.currentPage).")
                        }
                    }
                }
            } catch {
                if self.debugLogging {
                    if let raw = String(data: data, encoding: .utf8) {
                        print("[SearchVM] Decoding error: \(error). Raw response: \(raw.prefix(300))...")
                    } else {
                        print("[SearchVM] Decoding error: \(error). Unable to print raw response.")
                    }
                } else {
                    print("[SearchVM] Decoding error: \(error)")
                }
            }
        }.resume()
    }
    
    func goBack() {
        if let previous = historyStack.popLast() {
            withAnimation {
                self.products = previous.products
                self.query = previous.query
                self.searchType = previous.searchType
                self.priceFrom = previous.priceFrom
                self.priceTo = previous.priceTo
                self.onSale = previous.onSale
                self.withinVendorSearch = previous.withinVendorSearch
                
                self.selectedCategoryID = previous.selectedCategoryID
                self.selectedTopCategoryID = previous.selectedTopCategoryID
                self.selectedSubcategoryID = previous.selectedSubcategoryID
                self.selectedSubcategoryIDs = previous.selectedSubcategoryIDs
                self.selectedTopCategoryName = previous.selectedTopCategoryName
                self.selectedSubcategoryName = previous.selectedSubcategoryName
                
                
                self.selectedLocationID = previous.selectedLocationID
                self.selectedTopLocationID = previous.selectedTopLocationID
                self.selectedSubLocationID = previous.selectedSubLocationID
                self.selectedSubLocationIDs = previous.selectedSubLocationIDs
                self.selectedTopLocationName = previous.selectedTopLocationName
                self.selectedSubLocationName = previous.selectedSubLocationName
                
                self.totalResults = previous.totalResults
                self.currentPage = 1
                self.currentRelatedID = previous.currentRelatedID
                self.currentVendorID = previous.currentVendorID
                self.vendor = []
                self.hasMorePages = false
                self.seenIDs = previous.seenIDs.isEmpty ? Set(self.products.map { $0.id }) : previous.seenIDs
            }
            if debugLogging {
                print("[SearchVM] Restored previous state. Disabled pagination until a new search.")
            }
        }
    }

    var canGoBack: Bool { !historyStack.isEmpty }
    func clearHistory() { historyStack = [] }

    private func pushHistory() {
        let entry = HistoryEntry(
            products: self.products,
            query: self.lastQuery,
            searchType: self.searchType,
            priceFrom: self.priceFrom,
            priceTo: self.priceTo,
            onSale: self.onSale,
            withinVendorSearch: self.withinVendorSearch,
            
            selectedCategoryID: self.selectedCategoryID,
            selectedTopCategoryID: self.selectedTopCategoryID,
            selectedSubcategoryID: self.selectedSubcategoryID,
            selectedSubcategoryIDs: self.selectedSubcategoryIDs,
            selectedTopCategoryName: self.selectedTopCategoryName,
            selectedSubcategoryName: self.selectedSubcategoryName,
            
            selectedLocationID: self.selectedLocationID,
            selectedTopLocationID: self.selectedTopLocationID,
            selectedSubLocationID: self.selectedSubLocationID,
            selectedSubLocationIDs: self.selectedSubLocationIDs,
            selectedTopLocationName: self.selectedTopLocationName,
            selectedSubLocationName: self.selectedSubLocationName,
            
            totalResults: self.totalResults,
            currentRelatedID: self.currentRelatedID,
            currentVendorID: self.currentVendorID,
            seenIDs: self.seenIDs
        )
        historyStack.append(entry)
    }
}

// MARK: - Category lookup + lazy loading (uses existing endpoints; minimal fetch)
extension SearchViewModel {
    // Resolves a vc into parent/sub IDs and names using cachedTopCategories and cachedSubcategoriesByParent.
    // Returns nil if names are not available in cache (no network here).
    func categoryInfo(for vc: Int) -> (parentID: Int, parentName: String?, subID: Int?, subName: String?)? {
        let topNameByID: [Int: String] = Dictionary(uniqueKeysWithValues: cachedTopCategories.map { ($0.id, $0.name) })
        
        if vc < 999 {
            let parentName = topNameByID[vc]
            return (parentID: vc, parentName: parentName, subID: nil, subName: nil)
        } else {
            guard let parentID = computeParentCategoryID(from: vc) else { return nil }
            let parentName = topNameByID[parentID]
            let subs = cachedSubcategoriesByParent[parentID]
            let subName = subs?.first(where: { $0.id == vc })?.name
            return (parentID: parentID, parentName: parentName, subID: vc, subName: subName)
        }
    }

    // Lazy-load top categories if empty (uses same endpoint as FiltersView)
    @MainActor
    func ensureTopCategoriesLoaded() async {
        guard cachedTopCategories.isEmpty else { return }
        let components = URLComponents.apiEndpoint("categories")
        guard let url = components.url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            struct DTO: Decodable { let id: Int; let name: String }
            let decoded = try JSONDecoder().decode([DTO].self, from: data)
            self.cachedTopCategories = decoded.map { CategoryItem(id: $0.id, name: $0.name) }
        } catch {
            // silent
        }
    }

    // Lazy-load subcategories for a parent if missing (uses same endpoint as FiltersView)
    @MainActor
    func ensureSubcategoriesLoaded(parentID: Int) async {
        if cachedSubcategoriesByParent[parentID] != nil { return }
        let components = URLComponents.apiEndpoint(
            "categories",
            queryItems: [URLQueryItem(name: "id", value: String(parentID))]
        )
        guard let url = components.url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            struct DTO: Decodable { let id: Int; let name: String }
            let decoded = try JSONDecoder().decode([DTO].self, from: data)
            let items = decoded.map { CategoryItem(id: $0.id, name: $0.name) }
            self.cachedSubcategoriesByParent[parentID] = items
        } catch {
            // silent
        }
    }
}

