//
//  BrowseView.swift
//
//  Created by Sean Naden on 25/10/2025.
//
import SwiftUI
import SDWebImageSwiftUI

// A lightweight Identifiable wrapper for presenting vendor detail via .sheet(item:)
private struct VendorItem: Identifiable {
    let id = UUID()
    let vendor: Vendor
}

struct BrowseView: View {
    @StateObject private var viewModel = SearchViewModel()
    @FocusState private var textFieldIsFocused: Bool
    @Environment(\.dismissSearch) private var dismissSearch
    @EnvironmentObject private var favorites: FavoritesStore

    // Layout toggle persisted like FavoritesView
    @AppStorage("browse_layout") private var showGrid: Bool = true
    @AppStorage("show_trending") private var showTrending: Bool = false
    
    // Persisted recent searches (most recent first)
    @AppStorage("recent_searches") private var recentSearchesData: Data = Data()
    private func readRecentSearches() -> [String] {
        if recentSearchesData.isEmpty { return [] }
        return (try? JSONDecoder().decode([String].self, from: recentSearchesData)) ?? []
    }

    private func writeRecentSearches(_ newValue: [String]) {
        recentSearchesData = (try? JSONEncoder().encode(newValue)) ?? Data()
    }

    // MARK: - Recent Searches
    
    private func clearRecentSearches() {
        writeRecentSearches([])
    }
    
    private func addRecentSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lower = trimmed.lowercased()
        var current = readRecentSearches().filter { $0.lowercased() != lower }
        current.insert(trimmed, at: 0)
        if current.count > 20 { current = Array(current.prefix(20)) }
        writeRecentSearches(current)
    }

    private func matchingRecents(for query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        // show recents that contain the query substring; prefer prefix matches by sorting
        let filtered = readRecentSearches().filter { $0.lowercased().contains(q) }
        // Sort: prefix matches first, then alphabetical
        return filtered.sorted { a, b in
            let al = a.lowercased(), bl = b.lowercased()
            let aPref = al.hasPrefix(q), bPref = bl.hasPrefix(q)
            if aPref != bPref { return aPref && !bPref }
            return al < bl
        }
    }

    // Visual feedback for clearing recents
    @State private var didClearHistory: Bool = false

    // Sheet presentation state
    @State private var showAboutSheet = false
    @State private var showContactSheet = false
    @State private var showFAQsSheet = false
    @State private var showPrivacySheet = false
    @State private var showTermsSheet = false
    @State private var showAddURLSheet = false
    @State private var showFavoritesSheet = false
    @State private var showAccountSheet = false
    // New: login sheet for context-aware Account action
    @State private var showLoginSheet = false

    @State private var showToTop = false
    @State private var showIntro = true
    @State private var showVendorScope = false
    @State private var showFiltersSheet = false

    // New: whether to apply existing filters to the next text search
    @State private var applyFiltersToNextSearch: Bool = false

    // Search suggestions state
    @State private var suggestions: [String] = []
    @State private var isFetchingSuggestions: Bool = false
    @State private var suggestTask: Task<Void, Never>? = nil
    
    // Suppress showing suggestions (both API and recents) when we've just executed a search
    @State private var suppressSuggestions: Bool = false

    private struct SuggestResponse: Decodable {
        let results: [String]
    }

    // Intro content state
    private let introFallback = "Shop for over 2,448,298 products in 14,538 stores from around New Zealand"
    @State private var introText: String = "Shop for over 2,448,298 products in 14,538 stores from around New Zealand"

    // Toast state
    @State private var lastUpdated: Date?
    @State private var showUpdatedToast: Bool = false

    // Login confirmation toast
    @State private var showLoginToast: Bool = false
    // Logout confirmation toast
    @State private var showLogoutToast: Bool = false

    // Selection for navigation
    @State private var selectedProduct: Product?

    // Vendor detail presentation using Identifiable item
    @State private var vendorItem: VendorItem?

    // Account/profile prefetch
    @State private var isFetchingProfile = false
    @State private var prefilledProfile: UserProfile? = nil

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let screenWidth = geometry.size.width
                let desiredItemWidth: CGFloat = 180
                let columnCount = max(Int(screenWidth / desiredItemWidth), 1)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: columnCount)

                ScrollViewReader { proxy in
                    ZStack {
                        contentArea(columns: columns, proxy: proxy)
                    }
                    .overlay(alignment: .top) {
                        Group {
                            if showUpdatedToast {
                                updatedMessage(
                                    message: "Updated",
                                    icon: "checkmark.circle.fill",
                                    iconColor: .green,
                                    animationValue: showUpdatedToast
                                )
                            } else if showLoginToast {
                                updatedMessage(
                                    message: "You have been logged in.",
                                    icon: "person.crop.circle.badge.checkmark",
                                    iconColor: .green,
                                    animationValue: showLoginToast
                                )
                            } else if showLogoutToast {
                                updatedMessage(
                                    message: "You have been logged out.",
                                    icon: "person.crop.circle.badge.xmark",
                                    iconColor: .green,
                                    animationValue: showLogoutToast
                                )
                            }
                        }
                    }
                    .task {
                        if viewModel.products.isEmpty && viewModel.searchType == "search" {
                            if showTrending {
                                // Persisted preference: load trending feed on first open
                                viewModel.query = "trending"
                                viewModel.search(reset: true, thisType: "search")
                            } else {
                                print("[ContentView] First-load trigger: refreshing first page (vq=, page=1)")
                                viewModel.refreshFirstPage()
                            }
                        }
                        await loadContent(id: 1)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                //textFieldIsFocused = false
            }
            //.background(Color(.systemBackground))
            .onChange(of: textFieldIsFocused) { _, focused in
                if viewModel.searchType == "vendor" {
                    if focused {
                        Task { try? await Task.sleep(nanoseconds: 150_000_000); showVendorScope = true }
                    } else {
                        showVendorScope = false
                    }
                } else {
                    showVendorScope = false
                }

                // When user focuses the search field during normal search, show the toggle and default it to OFF
                if viewModel.searchType == "search" && focused {
                    applyFiltersToNextSearch = false
                    suppressSuggestions = false
                }

                // When the search field loses focus, hide any visible suggestions and stop fetching
                if focused == false {
                    suggestions = []
                    isFetchingSuggestions = false
                    suggestTask?.cancel()
                    suppressSuggestions = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    
                    //if viewModel.canGoBack {
                        
                   // } else {
                        
                        HStack {
                            Button {
                                viewModel.goBack()
                                textFieldIsFocused = false
                                dismissSearch()
                                showIntro = false
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                            .opacity(viewModel.canGoBack ? 1.0 : 0.1)
                            informationIcon
                        }
                    //}
                    
               }
                ToolbarItem(placement: .principal) {
                    Button(action: {
                        // Full reset to initial state
                        dismissSearch()
                        textFieldIsFocused = false
                        
                        
                        viewModel.resetFilters()
                        // 1) Clear navigation history first so we can't go back into vendor
                        viewModel.clearHistory()
                        // 4) Trigger a fresh normal search (empty query => first-open feed)
                        viewModel.search(reset: true, thisType: "search")
                        // 5) Intro UI back on
                        showIntro = true
                    }) {
                        Image("vendorama")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 111, height: 28)
                            //.padding(.leading, 10)
                            //.padding(.trailing, 10)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                            favoritesIcon
                            accountIcon
                    }
                }
            }
            //.glassEffect()
            .navigationDestination(item: $selectedProduct) { product in
                ProductDetailView(product: product, viewModel: viewModel)
            }
            //.navigationBarHidden(showToTop)
            //.transition(.move(edge:.top))
        }
        
        .sheet(isPresented: $showFavoritesSheet) {
            NavigationView {
                FavoritesView(viewModel: viewModel)
                    .navigationTitle("Favourites")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showFavoritesSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showAboutSheet) {
            NavigationView {
                AboutView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showAboutSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showContactSheet) {
            NavigationView {
                ContactView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showContactSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showFAQsSheet) {
            NavigationView {
                FAQsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showFAQsSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            NavigationView {
                PrivacyView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showPrivacySheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showTermsSheet) {
            NavigationView {
                TermsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showTermsSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showAddURLSheet) {
            NavigationView {
                AddURLView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showAddURLSheet = false }
                        }
                    }
            }
        }
        .sheet(item: $vendorItem) { item in
            NavigationView {
                VendorDetailView(vendor: item.vendor)
                    //.navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { vendorItem = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showFiltersSheet) {
            NavigationView {
                FiltersView(
                    viewModel: viewModel,
                    priceFrom: $viewModel.priceFrom,
                    priceTo: $viewModel.priceTo,
                    onApply: {
                        viewModel.currentPage = 1
                        viewModel.refreshFirstPage()
                        showFiltersSheet = false
                        
                    },
                    onClear: {
                        viewModel.priceFrom = nil
                        viewModel.priceTo = nil
                        viewModel.onSale = false
                        // Comment out raw resets for testing
                        // viewModel.priceFromRaw = nil
                        // viewModel.priceToRaw = nil
                        viewModel.restrictedOnly = false
                        
                        // Clear category selections
                        viewModel.selectedTopCategoryID = nil
                        viewModel.selectedTopCategoryName = nil
                        viewModel.selectedSubcategoryID = nil
                        viewModel.selectedSubcategoryName = nil
                        
                        // Clear category selections
                        viewModel.selectedTopLocationID = nil
                        viewModel.selectedTopLocationName = nil
                        viewModel.selectedSubLocationID = nil
                        viewModel.selectedSubLocationName = nil
                        
                        viewModel.currentPage = 1
                        viewModel.refreshFirstPage()
                        showFiltersSheet = false
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            // Simply dismiss the sheet; do not apply filters
                            showFiltersSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            NotificationCenter.default.post(name: .filtersDoneTapped, object: nil)
                        }
                    }
                }
            }
            
            // Trigger the same flow as tapping Done
            Button(action: {
                NotificationCenter.default.post(name: .filtersDoneTapped, object: nil)
            }) {
                // Make the entire visual area tappable
                HStack {
                    Spacer()
                    Text("Apply Filters")
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
            .padding(16)
            .background(Color(.systemBackground))
        }
        
        // Login sheet: shown when user taps Account while logged out
        .sheet(isPresented: $showLoginSheet) {
            NavigationView {
                LoginView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showLoginSheet = false }
                        }
                    }
            }
        }
        // Account sheet now passes prefilledProfile to AccountView
        .sheet(isPresented: $showAccountSheet) {
            NavigationView {
                AccountView(prefill: prefilledProfile)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showAccountSheet = false }
                        }
                    }
            }
        }
        // Observe login completion to show confirmation and refresh UI
        .onReceive(NotificationCenter.default.publisher(for: .didLogin).receive(on: RunLoop.main)) { _ in
            // Close login sheet if still open
            showLoginSheet = false
            // Show confirmation toast
            showLoginToastBriefly()
            // No need to do anything else; isLoggedIn reads from UserDefaults and will flip
        }
        .onDisappear {
            suggestTask?.cancel()
        }
    }
    
    // MARK: - Extracted content to simplify type-checking

    @ViewBuilder
    private func contentArea(columns: [GridItem], proxy: ScrollViewProxy) -> some View {
        Group {
            headerIntro

            if viewModel.searchType == "vendor",
               (showVendorScope || viewModel.withinVendorSearch),
               let vName = viewModel.vendor.first?.name {
                HStack {
                    Toggle(isOn: $viewModel.withinVendorSearch) {
                        HStack(spacing: 4) {
                            Text("within \(vName)")
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .scaleEffect(0.9).padding(.trailing, 4)
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 0)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            else if viewModel.searchType == "search" && viewModel.activeFiltersCount > 0 && textFieldIsFocused {
                let filterCount = viewModel.activeFiltersCount
                HStack {
                    // Real toggle: default OFF on focus; ON means include filters in next search
                    Toggle(isOn: $applyFiltersToNextSearch) {
                        HStack(spacing: 4) {
                            Text("with \(filterCount) filters")
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .scaleEffect(0.9)
                    .padding(.trailing, 4)
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 0)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                
            }
            
            if viewModel.searchType == "vendor" {
                headerVendor
            }

            HStack {
                layoutTitle
                Spacer()
                if viewModel.searchType == "search" {
                    layoutFiltersButton
                        .buttonStyle(.plain)
                        .allowsHitTesting(true)
                        .padding(.trailing, -16)
                }
                layoutToggleButton
                    .buttonStyle(.plain)
                    .allowsHitTesting(true)
                    .padding(0)
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
            .zIndex(1)

            if showGrid {
                gridMode(columns: columns, proxy: proxy)
            } else {
                listMode(proxy: proxy)
            }
            
            
        }
        .padding(EdgeInsets(top: 0, leading: 7, bottom: 0, trailing: 7))
        .navigationBarTitleDisplayMode(.inline)
        // search box
        .searchable(
            text: Binding<String>(
                get: {
                    let q = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                    return SearchViewModel.excludedQueries.contains(q.lowercased()) ? "" : viewModel.query
                },
                set: { newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if SearchViewModel.excludedQueries.contains(trimmed.lowercased()) {
                        viewModel.query = ""
                    } else {
                        viewModel.query = newValue
                    }
                }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "discover, shop, buy ..."
        )
        .onSubmit(of: .search) {
            suppressSuggestions = true
            if viewModel.searchType == "vendor", viewModel.withinVendorSearch {
                // vendor path ignores the toggle and refreshes
                viewModel.currentPage = 1
                viewModel.refreshFirstPage()
                addRecentSearch(viewModel.query)
            } else {
                // apply filters based on the toggle
                if applyFiltersToNextSearch {
                    viewModel.search(reset: true, thisType: "search")
                    addRecentSearch(viewModel.query)
                } else {
                    // clear filters then search
                    viewModel.priceFrom = nil
                    viewModel.priceTo = nil
                    viewModel.onSale = false
                    viewModel.restrictedOnly = false
                    viewModel.selectedTopCategoryID = nil
                    viewModel.selectedTopCategoryName = nil
                    viewModel.selectedSubcategoryID = nil
                    viewModel.selectedSubcategoryName = nil
                    viewModel.selectedTopLocationID = nil
                    viewModel.selectedTopLocationName = nil
                    viewModel.selectedSubLocationID = nil
                    viewModel.selectedSubLocationName = nil
                    viewModel.search(reset: true, thisType: "search")
                    addRecentSearch(viewModel.query)
                }
            }
        }
        .searchSuggestions {
            /*
             // this is unnecessary, causes a screen jump
            if isFetchingSuggestions {
                HStack {
                    ProgressView()
                    Text("Searching suggestions…")
                }
            }
             */
            if textFieldIsFocused && suppressSuggestions == false && viewModel.query != viewModel.lastQuery {
                let recents = matchingRecents(for: viewModel.query)
                let apiItems = suggestions
                let dedupedAPI = apiItems.filter { api in
                    !recents.contains(where: { $0.caseInsensitiveCompare(api) == .orderedSame })
                }
                let combined = recents + dedupedAPI
                if !combined.isEmpty {
                    ForEach(combined, id: \.self) { item in
                        HStack {
                            Button {
                                // Apply the suggestion to the query and submit a search
                                suggestTask?.cancel()
                                isFetchingSuggestions = false
                                suggestions = []
                                suppressSuggestions = true
                                viewModel.query = item
                                textFieldIsFocused = false
                                dismissSearch()
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 120_000_000)
                                    if viewModel.searchType == "vendor", viewModel.withinVendorSearch {
                                        viewModel.currentPage = 1
                                        viewModel.refreshFirstPage()
                                        addRecentSearch(viewModel.query)
                                    } else {
                                        if applyFiltersToNextSearch {
                                            viewModel.search(reset: true, thisType: "search")
                                            addRecentSearch(viewModel.query)
                                        } else {
                                            // Clear filters for this search
                                            viewModel.priceFrom = nil
                                            viewModel.priceTo = nil
                                            viewModel.onSale = false
                                            viewModel.restrictedOnly = false
                                            viewModel.selectedTopCategoryID = nil
                                            viewModel.selectedTopCategoryName = nil
                                            viewModel.selectedSubcategoryID = nil
                                            viewModel.selectedSubcategoryName = nil
                                            viewModel.selectedTopLocationID = nil
                                            viewModel.selectedTopLocationName = nil
                                            viewModel.selectedSubLocationID = nil
                                            viewModel.selectedSubLocationName = nil
                                            viewModel.search(reset: true, thisType: "search")
                                            addRecentSearch(viewModel.query)
                                        }
                                    }
                                    // Ensure suggestions stay hidden after navigation
                                    suggestTask?.cancel()
                                    isFetchingSuggestions = false
                                    suggestions = []
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 12)
                                    Text(item)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 0)
                                .padding(.horizontal, 0)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                viewModel.query = item
                            } label: {
                                Image(systemName: "arrow.up.left.circle")
                                        .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                        }
                    }
                    
                    // Clear history row
                    if !recents.isEmpty {
                        HStack {
                            Button {
                                // Clear only the recents, keep API suggestions intact
                                clearRecentSearches()
                                // Provide subtle visual feedback
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    didClearHistory = true
                                }
                                // Reset the flag after a short delay so it can animate again next time
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        didClearHistory = false
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.tertiary)
                                    Text("Clear history")
                                        .foregroundStyle(.secondary)
                                        .opacity(didClearHistory ? 0.5 : 1.0)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
        .searchFocused($textFieldIsFocused)
        .onChange(of: viewModel.query) { oldValue, newValue in
            // Cancel any in-flight suggestion task
            suggestTask?.cancel()
            suppressSuggestions = false

            // Trim and guard against short/empty queries and excluded queries
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || SearchViewModel.excludedQueries.contains(trimmed.lowercased()) {
                suggestions = []
                isFetchingSuggestions = false
                return
            }
            // For very short queries, skip API but still allow recents to appear
            if trimmed.count < 2 {
                suggestions = []
                isFetchingSuggestions = false
                return
            }

            // Debounce fetch ~250ms
            suggestTask = Task { [trimmed] in
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                    try Task.checkCancellation()
                    await fetchSuggestions(for: trimmed)
                } catch {
                    // cancellation or errors are ignored for UX smoothness
                }
            }
        }
        .refreshable {
            print("[ContentView] Pull-to-refresh triggered")
            hapticRefresh()
            withAnimation(.easeInOut) {
                proxy.scrollTo("top", anchor: .top)
            }
            viewModel.refreshFirstPage()
        }
        .onChange(of: viewModel.isLoading) { oldValue, newValue in
            if oldValue == true && newValue == false {
                lastUpdated = Date()
                // Hide any lingering suggestions after results load
                suggestTask?.cancel()
                isFetchingSuggestions = false
                suggestions = []
                suppressSuggestions = true
            }
        }
    }
    
    // Unified toast view builder
    private func updatedMessage(
        message: String,
        icon: String,
        iconColor: Color,
        animationValue: Bool
    ) -> some View {
        VStack {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(message)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glassEffect()
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer() // Push content to the top
        }
        //.ignoresSafeArea(edges: .top)
        .zIndex(1000)
        .allowsHitTesting(false)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.5), value: animationValue)
    }

    @MainActor
    private func showLoginToastBriefly() {
        withAnimation { showLoginToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation { showLoginToast = false }
        }
    }

    @MainActor
    private func showLogoutToastBriefly() {
        withAnimation { showLogoutToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation { showLogoutToast = false }
        }
    }

    @MainActor
    private func fetchSuggestions(for query: String) async {
        isFetchingSuggestions = true
        defer { isFetchingSuggestions = false }

        // Build using the shared apiEndpoint helper so API key, token, etc. are appended.
        let components = URLComponents.apiEndpoint(
            "suggest",
            queryItems: [
                URLQueryItem(name: "vq", value: query)
            ]
        )
        guard let url = components.url else {
            suggestions = []
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                suggestions = []
                return
            }
            let decoded = try JSONDecoder().decode(SuggestResponse.self, from: data)
            //var seen = Set<String>()
            //let uniquePreservingOrder = decoded.results.filter { seen.insert($0).inserted }
            //suggestions = Array(uniquePreservingOrder.prefix(12))
            suggestions = Array(decoded.results.prefix(12))
        } catch {
            suggestions = []
        }
    }

    // MARK: - Subviews/helpers inside BrowseView

    private var layoutFiltersButton: some View {
        Button {
            showFiltersSheet = true
        } label: {
            HStack(spacing: 0) {
                // line.3.horizontal.decrease // slider.horizontal.3
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            .frame(width: 56, height: 20, alignment: .center)

            if viewModel.activeFiltersCount > 0 {
                VStack(alignment: .leading) {
                    Text("\(viewModel.activeFiltersCount)")
                        .font(.system(size: 11))
                        .bold()
                        .frame(alignment: .top)
                        .padding(5)
                        .foregroundStyle(.white)
                        .cornerRadius(22)
                        .clipped()
                        .background(filtersIconBackground)
                        .clipShape(Circle())
                }
                .padding(.leading, -28)
                .padding(.trailing, -28)
                .padding(.top, -2)
                .offset(x: -2, y: -6.0)
            }
        }
        .accessibilityLabel("Search filters")
        .buttonStyle(.plain)
    }

    private var layoutToggleButton: some View {
        Button {
            withAnimation(.easeInOut) {
                showGrid.toggle()
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: showGrid ? "list.bullet" : "square.grid.2x2")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, showGrid ? 8 : 6)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            .frame(width: 56, height: 20, alignment: .center)
        }
        .accessibilityLabel(showGrid ? "Show list" : "Show grid")
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var headerVendor: some View {
        if viewModel.searchType == "vendor", let v = viewModel.vendor.first {
            Button {
                vendorItem = VendorItem(vendor: v)
            } label: {
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        if let thumb = v.thumb, let url = apiURL(thumb) {
                            WebImage(url: url)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                                .overlay(Rectangle().stroke(Color(UIColor.systemGray5), lineWidth: 1).cornerRadius(9))
                                .clipped()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(9)
                                .contentShape(Rectangle())
                                .blendMode(.multiply)
                        } else {
                            Circle()
                                .fill(Color(.secondarySystemBackground))
                                .frame(width: 60, height: 60)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(v.name ?? "Store")
                                    .font(.headline)
                                if v.licence != 0 {
                                    Image(systemName: "checkmark.seal.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 16, height: 16)
                                        .offset(y: 2)
                                        .foregroundStyle(Color(.blue))
                                }
                                
                              
                                // TODO: add favorites button
                                let vendorFavoriteID = "\(v.vendor_id ?? 0).0"
                                Button {
                                    favorites.toggleFavorite(vendorFavoriteID)
                                } label: {
                                    Image(systemName: favorites.isFavorite(vendorFavoriteID) ? "heart.fill" : "heart")
                                        .foregroundStyle(favorites.isFavorite(vendorFavoriteID) ? .purple : .secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(favorites.isFavorite(vendorFavoriteID) ? "Remove vendor from favourites" : "Add vendor to favourites")
                            }
                            /*
                            HStack {
                                
                                
                                if let clicks = v.clicks {
                                    Text("\(clicks) clicks")
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20.0)
                                                .stroke(Color.secondary, lineWidth: 1)
                                                .opacity(0.3)
                                            )
                                }
                                
                                if let views = v.views {
                                    Text("\(views) views")
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20.0)
                                                .stroke(Color.secondary, lineWidth: 1)
                                                .opacity(0.3)
                                            )
                                }
                                
                            }
                             */
                            let addr: [String] = [
                                v.address2 ?? "",
                                v.city ?? ""
                            ].filter { !$0.isEmpty }
                            if !addr.isEmpty {
                                Text(addr.joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let urlStr = v.url, let host = URL(string: urlStr)?.host {
                                Text(host)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 38)
                }
                .padding(.top, 4)
                .padding(.bottom, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var headerIntro: some View {
        if showIntro && viewModel.searchType == "search" && (viewModel.lastQuery.isEmpty || viewModel.lastQuery == "trending") && viewModel.activeFiltersCount == 0 {
            Text(.init(introText))
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .center)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .padding(EdgeInsets(top: 0, leading: 29, bottom: 2, trailing: 33))
        } else {
            EmptyView()
        }
    }

    // Helper used by layoutTitle to build the results message string
    private func resultsMessage() -> String {
        let base = "\(viewModel.totalResults ?? 0) results "
        var parts: [String] = []
        if let from = viewModel.priceFrom, let to = viewModel.priceTo {
            parts.append("$\(from) to $\(to)")
        } else if let from = viewModel.priceFrom {
            parts.append("over $\(from)")
        } else if let to = viewModel.priceTo {
            parts.append("under $\(to)")
        }
        if viewModel.onSale {
            parts.append("on sale")
        }
        if let cat = cleanCategoryName(viewModel.selectedSubcategoryName ?? viewModel.selectedTopCategoryName) {
          parts.append("in \"" + cat + "\"")

        }
        // Location/subLocation name if available (prefer subLocation)
        if let locName = viewModel.selectedSubLocationName ?? viewModel.selectedTopLocationName, !locName.isEmpty {
            // Truncate anything from the first "(" onward and trim whitespace/commas
            let cleaned: String = {
                if let parenIndex = locName.firstIndex(of: "(") {
                    return locName[..<parenIndex].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
                } else {
                    return locName.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
                }
            }()
            if !cleaned.isEmpty {
                parts.append("near " + cleaned)
            }
        }
        return base + parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var layoutTitle: some View {
        HStack {
            if viewModel.searchType == "search" && viewModel.activeFiltersCount == 0 && (viewModel.lastQuery.isEmpty || viewModel.lastQuery == "trending" || showTrending == true) {
                HStack {
                    if viewModel.lastQuery == "", showTrending == false {
                        Text("New")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20.0)
                                    .stroke(Color.secondary, lineWidth: 1)
                            )
                        Button("Trending", action: {
                            viewModel.query = "trending"
                            viewModel.search(reset: true, thisType: "search")
                            showTrending = true
                            //textFieldIsFocused = false
                            dismissSearch()
                        })
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20.0)
                                .stroke(Color.secondary, lineWidth: 1)
                                .opacity(0.3)
                        )
                    } else {
                        Button("New", action: {
                            viewModel.query = ""
                            viewModel.search(reset: true, thisType: "search")
                            showTrending = false
                            //textFieldIsFocused = false
                            dismissSearch()
                        })
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20.0)
                                .stroke(Color.secondary, lineWidth: 1)
                                .opacity(0.3)
                        )
                        Text("Trending")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20.0)
                                    .stroke(Color.secondary, lineWidth: 1)
                            )
                    }
                }
                .padding(0)
            }
            else if viewModel.searchType == "related" {
                let text = viewModel.products.first?.name ?? ""
                if text != "" {
                    Text("Showing more like \"\(text)\"")
                }
            }
            else if viewModel.searchType == "vendor" {
                if let categories = viewModel.vendor.first?.categories, !categories.isEmpty {
                    Menu {
                        Button("All categories", action: {
                            if viewModel.selectedCategoryID != nil {
                                viewModel.selectedCategoryID = nil
                                viewModel.refreshFirstPage()
                            }
                        })
                        ForEach(categories, id: \.self) { cat in
                            let isSelected = (viewModel.selectedCategoryID == cat.id)
                            Button(action: {
                                if viewModel.selectedCategoryID != cat.id {
                                    viewModel.selectedCategoryID = cat.id
                                    viewModel.refreshFirstPage()
                                }
                            }) {
                                HStack {
                                    Text(cat.name ?? "Category")
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text(selectedCategoryTitle(categories: categories))
                                .lineLimit(1)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    .padding(.leading, -4)
                    if viewModel.vendor.first?.products != nil {
                        Text("(\(viewModel.totalResults ?? 0))")
                    }
                } else if viewModel.totalResults != nil {
                    Text("\(viewModel.totalResults ?? 0) products")
                }
            }
            else if (viewModel.searchType == "search" || viewModel.searchType == "vendor") && viewModel.totalResults != nil && viewModel.products.count > 0 {
                Text(resultsMessage())
            }
            else if viewModel.searchType == "search" && !viewModel.query.isEmpty {
                //Text("No results 1")
            }
            else if viewModel.searchType == "search" && viewModel.lastQuery.isEmpty {
                //Text("No results 1")
            }
        }
        .padding(.bottom, 0)
        .foregroundStyle(.secondary)
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(x: 14.0, y: 0.0)
    }

    private func selectedCategoryTitle(categories: [Vendor.Category]) -> String {
        if let sel = viewModel.selectedCategoryID, let match = categories.first(where: { $0.id == sel }) {
            return match.name ?? "Category"
        } else {
            return "All categories"
        }
    }

    @ViewBuilder
    private func ToTop(proxy: ScrollViewProxy) -> some View {
        if showToTop  {
            /**/
            Button(action: {
                withAnimation {
                    proxy.scrollTo("top", anchor: .top) // Scroll to the top
                }
            }) {
                Label("", systemImage: "chevron.up.circle.fill")
            }
                .buttonStyle(.plain)
                .font(.system(size: 50))
                .foregroundStyle(Color.gray.opacity(0.1))
                .padding(10)
                .frame(width: 80, height: 80, alignment: .center)
                .contentShape(Rectangle())
                .clipped()
                .clipShape(Circle())
                .offset(x: 4)
            
            /*
             
             Button(action: {
                 withAnimation {
                     proxy.scrollTo("top", anchor: .top) // Scroll to the top
                 }
             }) {
                 Label("", systemImage: "chevron.up")
             }
             
                 //.buttonStyle(.plain)
                 .font(.system(size: 30))
                 .foregroundStyle(.secondary)
                 .padding(.leading, 8)
                 .padding(.top, 18)
                 .padding(.bottom, 18)
                 .opacity(0.3)
                 .bold()
                 .frame(width: 54, height: 54, alignment: .center)
                 .clipped()
                 .clipShape(Circle())
                 .contentShape(Rectangle())
                 .glassEffect()
             */
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var emptyOverlayIfNoResults: some View {
        if !viewModel.isLoading && viewModel.hasSearched && viewModel.products.isEmpty && !viewModel.query.isEmpty {
            VStack {
                Text("No results")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 20)
            .font(.system(size: 13))
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var emptyStateIfNeeded: some View {
        if !viewModel.isLoading && viewModel.hasSearched && viewModel.products.isEmpty && !viewModel.query.isEmpty {
            VStack {
                Text("No results")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 20)
            .font(.system(size: 13))
        } else {
            EmptyView()
        }
    }

    private struct ContentResponse: Decodable {
        let content: String
        let product: String? // Make optional to match actual payload
    }
    
    @MainActor
    private func loadContent(id: Int = 1) async {
        let components = URLComponents.apiEndpoint(
            "content",
            queryItems: [
                URLQueryItem(name: "y", value: "3"),
                URLQueryItem(name: "id", value: "\(id)")
            ]
        )
        guard let url = components.url else {
            if id == 1 { introText = introFallback }
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                if id == 1 { introText = introFallback }
                return
            }
            let decoded = try JSONDecoder().decode(ContentResponse.self, from: data)
            let content = decoded.content
            if content.isEmpty {
                if id == 1 { introText = introFallback }
            } else {
                introText = content
            }
        } catch {
            if id == 1 {
                print("id 1 not called \(url)")
                introText = introFallback
            }
        }
    }

    @MainActor
    func loadProduct(id: String) async {
        let components = URLComponents.apiEndpoint(
            "product",
            queryItems: [
                // todo, add comments:
                //URLQueryItem(name: "comments", value: "1"),
                URLQueryItem(name: "id", value: "\(id)")
            ]
        )
        guard let url = components.url else {
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return
            }
            let decoded = try JSONDecoder().decode(ContentResponse.self, from: data)
            let product = decoded.product
            if product?.isEmpty == true {
            } else {
            }
        } catch {
        }
    }

    // MARK: - Grid and List modes

    @ViewBuilder
    private func gridMode(columns: [GridItem], proxy: ScrollViewProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 1)
                        .id("top")
                    
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(viewModel.products.enumerated()), id: \.element.id) { index, product in
                            let onSelect: () -> Void = {
                                selectedProduct = product
                            }
                            // Detect first product without needing an index
                            let isFirst = (product.id == viewModel.products.first?.id)
                            
                            Group {
                                if viewModel.searchType == "related", isFirst {
                                    ProductRowViewRelated(product: product, viewModel: viewModel, onSelect: onSelect)
                                } else {
                                    ProductRowView(product: product, viewModel: viewModel, onSelect: onSelect)
                                }
                            }
                            
                            .onAppear {
                                viewModel.loadNextPageIfNeeded(currentItem: product)
                                
                                if viewModel.searchType == "search" || viewModel.searchType == "related" {
                                    let shouldShow = index >= 25
                                    let shouldHide = index <= 12
                                    if shouldShow, showToTop == false {
                                        showToTop = true
                                        showIntro = false
                                    }
                                    if shouldHide, showToTop == true { showToTop = false }
                                    //if showIntro == true, index >= 12 { showIntro = false }
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.vertical, 12)
                    }
                }
                
            }
            .overlay(emptyOverlayIfNoResults)
            .overlay(
                ToTop(proxy: proxy)
                , alignment: .bottom)
        }
    }

    @ViewBuilder
    private func listMode(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 1)
                    .id("top")

                LazyVStack(spacing: 0) {
                    
                    ForEach(Array(viewModel.products.enumerated()), id: \.element.id) { index, product in
                        ProductListRow(product: product, viewModel: viewModel, onSelect: {
                            selectedProduct = product
                        })
                        .onAppear {
                            viewModel.loadNextPageIfNeeded(currentItem: product)
                           
                            if viewModel.searchType == "search" || viewModel.searchType == "related" {
                                let shouldShow = index >= 25
                                let shouldHide = index <= 12
                                if shouldShow, showToTop == false { showToTop = true }
                                if shouldHide, showToTop == true { showToTop = false }
                            }
                        }
                        Divider()
                            .padding(10)
                    }
                }

                if viewModel.isLoading {
                    ProgressView()
                        .padding(.vertical, 12)
                }
            }
        }
        .overlay(emptyOverlayIfNoResults)
        .overlay(
            ToTop(proxy: proxy)
            , alignment: .bottom)
    }

    // MARK: - Haptics
    private func hapticRefresh() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    // MARK: - Toast
    private func showJustUpdatedToast() {
        withAnimation {
            showUpdatedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showUpdatedToast = false
            }
        }
    }

    // FAVORITES
    
    private var favoritesIcon: some View {
        
        Button {
            showFavoritesSheet = true
        } label: {
            Image(systemName: favoritesIconName)
                .padding(0)
            
            VStack(alignment: .leading) {
                Text("\(favorites.favorites.count)")
                    .font(.system(size: 11))
                    .bold()
                    .frame(alignment: .top)
                    .padding(favorites.favorites.isEmpty ? 0:5)
                    .foregroundStyle(.white)
                    .cornerRadius(22)
                    .clipped()
                    .background(favoritesIconColor)
                    .clipShape(Circle())
            }
            .padding(0)
            .offset(x: -16, y: -6.0)
            .opacity(favoritesTotalOpacity)
        }
        .accessibilityLabel("Favorites")
        .foregroundStyle(.secondary)
        .opacity(favoritesIconOpacity)
        
    }
    private var favoritesIconName: String {
        favorites.favorites.isEmpty ? "heart" : "heart"
    }
    private var favoritesIconColor: Color {
        favorites.favorites.isEmpty ? .secondary : .purple
    }
    private var favoritesIconOpacity: Double {
        favorites.favorites.isEmpty ? 0.8 : 1.0
    }
    private var favoritesTotalOpacity: Double {
        favorites.favorites.isEmpty ? 0.0 : 1.0
    }
    private var favoritesIconBackground: Double {
        favorites.favorites.isEmpty ? 0.4 : 1.0
    }
    private var filtersIconBackground: Color {
        Color(red: 191 / 255, green: 49 / 255, blue: 0 / 255)
    }
    
    private var toTopOpacity: Double {
        viewModel.searchType == "search" && showToTop == true ? 1.0 : 0.0
    }
    
    
    // INFORMATION
    
    private var informationIcon: some View {
        Menu {
            Button {
                showAboutSheet = true
            } label: {
                Label("About", systemImage: "info.circle")
            }
            Button {
                showContactSheet = true
            } label: {
                Label("Contact Us", systemImage: "envelope")
            }
            Button {
                showAddURLSheet = true
            } label: {
                Label("Add Store", systemImage: "storefront")
            }
            Button {
                showFAQsSheet = true
            } label: {
                Label("FAQs", systemImage: "questionmark.circle")
            }
            Button {
                showPrivacySheet = true
            } label: {
                Label("Privacy Policy", systemImage: "lock.circle")
            }
            Button {
                showTermsSheet = true
            } label: {
                Label("Terms", systemImage: "checkmark.shield")
            }
            Divider()
            Button {
                print("[ContentView] Manual refresh tapped")
                hapticRefresh()
                viewModel.refreshFirstPage()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        } label: {
            Label("Information", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .padding(.horizontal, 2)
        }
        .tint(.secondary)
        .accessibilityLabel("Information")
    }
    
    // ACCOUNT
    
    
    private var loginButton: some View {
        if isLoggedIn {
            Button(role: .destructive) {
                // Log out: clear stored email/first name; keep anonymous identity
                UserIdentityClient.logout()
                // Close any presented sheets
                showAccountSheet = false
                showLoginSheet = false
                print("[Account] Logged out. email=\(UserIdentityClient.storedEmail() ?? "(nil)")")
                // Show logout confirmation toast
                showLogoutToastBriefly()
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } else {
            Button {
                showAccountSheet = false
                showLoginSheet = true
            } label: {
                Label("Log In", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }
     
    private var accountButton: some View {
        
        Button {
            print("[Account] isLoggedIn=\(isLoggedIn) email=\(UserIdentityClient.storedEmail() ?? "(nil)") uid=\(String(describing: UserIdentityClient.userID())) tokenEmpty=\(UserIdentityClient.token()?.isEmpty ?? true)")
            if isLoggedIn {
                Task { await openAccount() }
            } else {
                // When logged out, open Login (not Account)
                showLoginSheet = false
                showAccountSheet = true
            }
        } label: {
            Label("Account", systemImage: "person.crop.circle")
        }
    }
    
    private var accountIcon: some View {
        Menu {
            if isLoggedIn {
                accountButton
                loginButton
            } else {
                loginButton
                accountButton
            }
        } label: {
            Label("Account", systemImage: "person.crop.circle")
                .labelStyle(.iconOnly)
                .padding(.leading, -14)
                .padding(.trailing, 10)
        }
        .tint(.secondary)
        .accessibilityLabel("Account")
    }

    // Session check for context-aware account action
    private var isLoggedIn: Bool {
        // Consider user "signed in" if we have a stored email, plus a valid identity
        if let email = UserIdentityClient.storedEmail(), !email.isEmpty,
           let uid = UserIdentityClient.userID(), uid > 0,
           let tok = UserIdentityClient.token(), !tok.isEmpty {
            return true
        }
        return false
    }

    private func openAccount() async {
        guard !isFetchingProfile else { return }
        isFetchingProfile = true
        defer { isFetchingProfile = false }

        // Ensure we have at least an identity
        _ = await UserIdentityClient.fetchOrCreate()

        // Optionally prefetch profile (AccountView can also fetch on appear)
        do {
            let (_, profile) = try await UserIdentityClient.fetchAccount()
            prefilledProfile = profile
        } catch {
            prefilledProfile = nil
        }
        
        await MainActor.run {
            showAccountSheet = true
        }
    }
    
    private func clearFilters() {

        viewModel.priceFrom = nil
        viewModel.priceTo = nil
        viewModel.onSale = false
        viewModel.restrictedOnly = false
        
        // Clear category selections
        viewModel.selectedTopCategoryID = nil
        viewModel.selectedTopCategoryName = nil
        viewModel.selectedSubcategoryID = nil
        viewModel.selectedSubcategoryName = nil
        
        // Clear category selections
        viewModel.selectedTopLocationID = nil
        viewModel.selectedTopLocationName = nil
        viewModel.selectedSubLocationID = nil
        viewModel.selectedSubLocationName = nil
        
        viewModel.currentPage = 1
        viewModel.refreshFirstPage()
    }
}

