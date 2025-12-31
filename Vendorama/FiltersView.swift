//
//  FiltersView.swift
//
//  Created by Sean Naden on 25/10/2025.
//

import SwiftUI

// Shared notification name used between FiltersView and ContentView
extension Notification.Name {
    static let filtersDoneTapped = Notification.Name("filtersDoneTapped")
}

// Simple model used by FiltersView for categories
struct CategoryItem: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct FiltersView: View {
    let viewModel: SearchViewModel
    @Binding var priceFrom: Int?
    @Binding var priceTo: Int?
    // Staged local value for On Sale that is applied on Done
    @State private var onSaleLocal: Bool = false
    var onApply: () -> Void
    var onClear: () -> Void

    @State private var fromText: String = ""
    @State private var toText: String = ""
    @State private var isDirty: Bool = false
    @Environment(\.dismiss) private var dismiss

    // Persist one-time age verification
    @AppStorage("ageVerified18Plus") private var ageVerified18Plus: Bool = false
    @State private var showAgeSheet: Bool = false
    @State private var pendingRestrictedToggle: Bool = false

    // Synthetic Adult category (only appended when restricted is enabled)
    private let adultCategory = CategoryItem(id: 900, name: "Adult")

    // Categories state
    @State private var topCategories: [CategoryItem] = []
    @State private var subcategories: [CategoryItem] = []
    @State private var selectedTopLocal: Int?
    // Keep single selection local var to avoid massive refactor, but subcategory UI will be multi-select.
    @State private var selectedSubLocal: Int?
    // NEW: Local multi-select set for subcategories
    @State private var selectedSubLocalSet: Set<Int> = []
    @State private var isLoadingTopCats: Bool = false
    @State private var isLoadingSubCats: Bool = false

    // Location state
    private struct LocationItem: Identifiable, Hashable {
        let id: Int
        let name: String
    }
    @State private var topLocations: [LocationItem] = []
    @State private var subLocations: [LocationItem] = []
    @State private var selectedTopLocationLocal: Int?
    @State private var selectedSubLocationLocal: Int?
    @State private var isLoadingTopLocations: Bool = false
    @State private var isLoadingSubLocations: Bool = false

    // Persist last selected locations for quick-apply
    @AppStorage("lastTopLocation") private var lastTopLocation: Int?
    @AppStorage("lastSubLocation") private var lastSubLocation: Int?
    @AppStorage("lastTopLocationName") private var lastTopLocationName: String?
    @AppStorage("lastSubLocationName") private var lastSubLocationName: String?

    var body: some View {
        Form {
            Section(header: Text("Price").font(.subheadline).foregroundStyle(.secondary).textCase(nil)) {
                HStack {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("from", text: $fromText)
                        .keyboardType(.numberPad)
                        .onChange(of: fromText) { _, _ in markDirtyIfNeeded() }
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("to", text: $toText)
                        .keyboardType(.numberPad)
                        .onChange(of: toText) { _, _ in markDirtyIfNeeded() }
                }
                HStack {
                    Toggle("On Sale", isOn: $onSaleLocal)
             }
          }
            

            // Location
            Section(header: Text("Location").font(.subheadline).foregroundStyle(.secondary).textCase(nil)) {
                // Top-level picker
                HStack {
                    Picker(selection: Binding<Int?>(
                        get: { selectedTopLocationLocal },
                        set: { newValue in
                            if selectedTopLocationLocal != newValue {
                                selectedTopLocationLocal = newValue
                                // Reset sub-location when parent changes
                                selectedSubLocationLocal = nil
                                subLocations = []
                                if let parentID = newValue {
                                    Task { await loadSubLocations(parentID: parentID) }
                                }
                                // Update VM names/IDs
                                if let id = newValue, let name = topLocations.first(where: { $0.id == id })?.name {
                                    viewModel.selectedTopLocationID = id
                                    viewModel.selectedTopLocationName = name
                                    // Persist last top
                                    lastTopLocation = id
                                    lastTopLocationName = name
                                } else {
                                    viewModel.selectedTopLocationID = nil
                                    viewModel.selectedTopLocationName = nil
                                }
                                // Clear sub name/ID in VM when parent changes
                                viewModel.selectedSubLocationID = nil
                                viewModel.selectedSubLocationName = nil

                                isDirty = true
                            }
                        }
                    )) {
                        Text("All Regions").tag(Int?.none)
                        ForEach(topLocations) { item in
                            Text(item.name).tag(Int?.some(item.id))
                        }
                    } label: {
                        EmptyView()
                    }
                    .padding(0)
                    .pickerStyle(.automatic)
                    .labelsHidden()
                    .tint(.primary)
                    if isLoadingTopLocations {
                        ProgressView().scaleEffect(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: -10)

                // SubLocation picker (appears when a parent is selected)
                if selectedTopLocationLocal != nil {
                    HStack {
                        Picker(selection: Binding<Int?>(
                            get: { selectedSubLocationLocal },
                            set: { newValue in
                                selectedSubLocationLocal = newValue
                                // Update VM subLocation name/ID
                                if let id = newValue, let name = subLocations.first(where: { $0.id == id })?.name {
                                    viewModel.selectedSubLocationID = id
                                    viewModel.selectedSubLocationName = name
                                    // Persist last sub
                                    lastSubLocation = id
                                    lastSubLocationName = name
                                } else {
                                    viewModel.selectedSubLocationID = nil
                                    viewModel.selectedSubLocationName = nil
                                }
                                isDirty = true
                            }
                        )) {
                            Text("All Suburbs").tag(Int?.none)
                            ForEach(subLocations) { item in
                                Text(item.name).tag(Int?.some(item.id))
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.automatic)
                        .labelsHidden()
                        .tint(.primary)
                        if isLoadingSubLocations {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                    .offset(x: -10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Quick-apply last location button (only when no current selection)
                if selectedSubLocationLocal == nil && selectedTopLocationLocal == nil {
                    if let lastSubID = lastSubLocation,
                       let lastSubName = lastSubLocationName,
                       !lastSubName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 8) {
                            Button("Select \(lastSubName)") {
                                // Ensure top is set; fallback to stored top if needed
                                if selectedTopLocationLocal == nil, let storedTop = lastTopLocation {
                                    selectedTopLocationLocal = storedTop
                                    if let topName = topLocations.first(where: { $0.id == storedTop })?.name {
                                        viewModel.selectedTopLocationID = storedTop
                                        viewModel.selectedTopLocationName = topName
                                    } else {
                                        viewModel.selectedTopLocationID = storedTop
                                        viewModel.selectedTopLocationName = lastTopLocationName
                                    }
                                    Task { await loadSubLocations(parentID: storedTop) }
                                }
                                // Apply sub
                                selectedSubLocationLocal = lastSubID
                                viewModel.selectedSubLocationID = lastSubID
                                viewModel.selectedSubLocationName = lastSubName
                                // Persist again
                                lastSubLocation = lastSubID
                                lastSubLocationName = lastSubName
                                isDirty = true
                            }
                            .buttonStyle(.borderless)

                            Button {
                                lastTopLocation = nil
                                lastSubLocation = nil
                                lastTopLocationName = nil
                                lastSubLocationName = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityLabel("Clear saved location")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)

                    } else if let lastTopID = lastTopLocation,
                              let lastTopName = lastTopLocationName,
                              !lastTopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 8) {
                            Button("Select \(lastTopName)") {
                                selectedTopLocationLocal = lastTopID
                                selectedSubLocationLocal = nil
                                subLocations = []
                                viewModel.selectedTopLocationID = lastTopID
                                viewModel.selectedTopLocationName = lastTopName
                                viewModel.selectedSubLocationID = nil
                                viewModel.selectedSubLocationName = nil
                                Task { await loadSubLocations(parentID: lastTopID) }
                                lastTopLocation = lastTopID
                                lastTopLocationName = lastTopName
                                isDirty = true
                            }
                            .buttonStyle(.borderless)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)

                            Button {
                                lastTopLocation = nil
                                lastSubLocation = nil
                                lastTopLocationName = nil
                                lastSubLocationName = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityLabel("Clear saved location")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    }
                } else if lastTopLocation != nil || lastSubLocation != nil {
                    Button {
                        lastTopLocation = nil
                        lastSubLocation = nil
                        lastTopLocationName = nil
                        lastSubLocationName = nil

                        selectedTopLocationLocal = nil
                        selectedSubLocationLocal = nil

                        viewModel.selectedTopLocationID = nil
                        viewModel.selectedTopLocationName = nil

                        viewModel.selectedSubLocationID = nil
                        viewModel.selectedSubLocationName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Clear saved location")
                }
            }

            // Categories
            Section(header: Text("Categories").font(.subheadline).foregroundStyle(.secondary).textCase(nil)) {
                // Top-level picker (single select)
                HStack {
                    Picker(selection: Binding<Int?>(
                        get: { selectedTopLocal },
                        set: { newValue in
                            if selectedTopLocal != newValue {
                                selectedTopLocal = newValue
                                // Reset subcategory when parent changes
                                selectedSubLocal = nil
                                selectedSubLocalSet = [] // clear multi-select when parent changes
                                subcategories = []

                                if let parentID = newValue {
                                    if let cached = viewModel.cachedSubcategoriesByParent[parentID] {
                                        subcategories = cached
                                        // Clear any sub selection because parent changed
                                        selectedSubLocal = nil
                                        selectedSubLocalSet = []
                                        viewModel.selectedSubcategoryID = nil
                                        viewModel.selectedSubcategoryName = nil
                                        viewModel.selectedSubcategoryIDs = []
                                    } else {
                                        Task { await loadSubcategories(parentID: parentID) }
                                    }
                                }

                                // Update VM names/IDs
                                if let id = newValue, let name = topCategories.first(where: { $0.id == id })?.name {
                                    viewModel.selectedTopCategoryID = id
                                    viewModel.selectedTopCategoryName = name
                                } else {
                                    viewModel.selectedTopCategoryID = nil
                                    viewModel.selectedTopCategoryName = nil
                                }
                                // Clear subcategory name/ID in VM when parent changes
                                viewModel.selectedSubcategoryID = nil
                                viewModel.selectedSubcategoryName = nil
                                viewModel.selectedSubcategoryIDs = []

                                if selectedTopLocal != 900 {
                                    viewModel.restrictedOnly = false
                                } else if selectedTopLocal == 900 {
                                    viewModel.restrictedOnly = true
                                }

                                isDirty = true
                            }
                        }
                    )) {
                        Text("All categories").tag(Int?.none)
                        ForEach(topCategories) { item in
                            Text(item.name).tag(Int?.some(item.id))
                        }
                    } label: {
                        EmptyView()
                    }
                    .padding(0)
                    .pickerStyle(.automatic)
                    .labelsHidden()
                    .tint(.primary)
                    if isLoadingTopCats {
                        ProgressView().scaleEffect(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: -10)

                // Subcategory multi-select (appears when a parent is selected)
                if selectedTopLocal != nil {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Inline Checkbox-style rows for multi-select subcategories
                            ForEach(subcategories) { item in
                                // Bind each control to membership in selectedSubLocalSet
                                Toggle(isOn: Binding<Bool>(
                                    get: { selectedSubLocalSet.contains(item.id) },
                                    set: { newValue in
                                        if newValue {
                                            selectedSubLocalSet.insert(item.id)
                                        } else {
                                            selectedSubLocalSet.remove(item.id)
                                        }
                                        // keep single local in sync loosely (optional)
                                        selectedSubLocal = selectedSubLocalSet.first
                                        isDirty = true
                                    }
                                )) {
                                    Text(item.name)
                                }
                                .toggleStyle(CheckboxToggleStyle())
                            }

                            // Convenience: "Select All" / "Clear All" for current subcategories
                            if !subcategories.isEmpty {
                                HStack(spacing: 12) {
                                    Button("Select All") {
                                        selectedSubLocalSet = Set(subcategories.map { $0.id })
                                        selectedSubLocal = selectedSubLocalSet.first
                                        isDirty = true
                                    }
                                    Button("Clear All") {
                                        selectedSubLocalSet = []
                                        selectedSubLocal = nil
                                        isDirty = true
                                    }
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            }

                            if isLoadingSubCats {
                                HStack {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Loading…")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 320, alignment: .leading)
                }
            }
            /**/

            if viewModel.selectedTopCategoryID == nil || viewModel.selectedTopCategoryID == 900 {
                Section {
                    Toggle("Adult/Restricted", isOn: Binding(
                        get: { viewModel.restrictedOnly },
                        set: { newValue in
                            // Only gate when turning ON
                            if newValue == true && ageVerified18Plus == false {
                                pendingRestrictedToggle = true
                                showAgeSheet = true
                            } else {
                                handleRestrictedToggleChange(newValue)
                            }
                        }
                        
                    ))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .fixedSize()
                    .scaleEffect(0.8)
                    .opacity(viewModel.restrictedOnly ? 1 : 0.6)
                }
                .listRowBackground(Color.clear)
                .padding(0)
                .padding(.bottom, 20)
                .listSectionSpacing(0)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
            Section {
                HStack {
                    Button("Clear All", role: .destructive) {
                        priceFrom = nil
                        priceTo = nil
                        onSaleLocal = false
                        viewModel.onSale = false
                        viewModel.restrictedOnly = false
                        fromText = ""
                        toText = ""
                        // Clear categories local + VM
                        selectedTopLocal = nil
                        selectedSubLocal = nil
                        selectedSubLocalSet = []
                        subcategories = []
                        viewModel.selectedTopCategoryID = nil
                        viewModel.selectedTopCategoryName = nil
                        viewModel.selectedSubcategoryID = nil
                        viewModel.selectedSubcategoryName = nil
                        viewModel.selectedSubcategoryIDs = []

                        // Clear locations local + VM
                        selectedTopLocationLocal = nil
                        selectedSubLocationLocal = nil
                        subLocations = []
                        viewModel.selectedTopLocationID = nil
                        viewModel.selectedTopLocationName = nil
                        viewModel.selectedSubLocationID = nil
                        viewModel.selectedSubLocationName = nil

                        removeAdultCategoryIfPresent()
                        // Also remove from VM cache to keep in sync
                        if viewModel.cachedTopCategories.contains(adultCategory) {
                            viewModel.cachedTopCategories.removeAll { $0 == adultCategory }
                        }

                        isDirty = false
                        onClear()
                    }
                    /*
                    Spacer()
                    Button("Reset 18+ flag") {
                        ageVerified18Plus = false
                    }
                     */
                }
            }
        }
        .navigationTitle("Filters")
        .onAppear {
            // Hydrate purely from Int? bindings
            fromText = priceFrom.map(String.init) ?? ""
            toText = priceTo.map(String.init) ?? ""
            // Hydrate staged On Sale from VM
            onSaleLocal = viewModel.onSale

            // Hydrate local category selections from VM
            selectedTopLocal = viewModel.selectedTopCategoryID
            selectedSubLocal = viewModel.selectedSubcategoryID
            // Initialize multi-select set from VM (prefer multi; include single if present)
            selectedSubLocalSet = viewModel.selectedSubcategoryIDs
            if let single = viewModel.selectedSubcategoryID {
                selectedSubLocalSet.insert(single)
            }

            isDirty = false

            // Load top categories (use cache if available)
            if !viewModel.cachedTopCategories.isEmpty {
                // Ensure VM cache is also consistent with restrictedOnly
                if viewModel.restrictedOnly {
                    if !viewModel.cachedTopCategories.contains(adultCategory) {
                        viewModel.cachedTopCategories.append(adultCategory)
                    }
                } else {
                    if viewModel.cachedTopCategories.contains(adultCategory) {
                        viewModel.cachedTopCategories.removeAll { $0 == adultCategory }
                    }
                }

                // Use the VM cache (now synchronized) as the local list
                topCategories = viewModel.cachedTopCategories

                // Adult category visibility MUST be applied before validating selection
                if viewModel.restrictedOnly {
                    appendAdultCategoryIfNeeded()
                } else {
                    removeAdultCategoryIfPresent()
                }

                // Validate after assigning from cache and ensuring Adult presence if needed
                if let selTop = selectedTopLocal, !topCategories.contains(where: { $0.id == selTop }) {
                    selectedTopLocal = nil
                    selectedSubLocal = nil
                    selectedSubLocalSet = []
                    subcategories = []
                    viewModel.selectedTopCategoryID = nil
                    viewModel.selectedTopCategoryName = nil
                    viewModel.selectedSubcategoryID = nil
                    viewModel.selectedSubcategoryName = nil
                    viewModel.selectedSubcategoryIDs = []
                }
            } else {
                Task { await loadTopCategories() }
            }

            // Load subcategories (use cache if available)
            if let parentID = selectedTopLocal {
                if let cached = viewModel.cachedSubcategoriesByParent[parentID] {
                    subcategories = cached
                    // Validate sub selections (multi)
                    let validIDs = Set(cached.map { $0.id })
                    selectedSubLocalSet = selectedSubLocalSet.intersection(validIDs)
                    // Validate single sub selection
                    if let selSub = selectedSubLocal, !cached.contains(where: { $0.id == selSub }) {
                        selectedSubLocal = nil
                    }
                } else {
                    Task { await loadSubcategories(parentID: parentID) }
                }
            }

            // Locations
            selectedTopLocationLocal = viewModel.selectedTopLocationID
            selectedSubLocationLocal = viewModel.selectedSubLocationID
            Task { await loadTopLocations() }
            if let parentID = selectedTopLocationLocal {
                Task { await loadSubLocations(parentID: parentID) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .filtersDoneTapped)) { _ in
            applyFilters()
            // Push staged On Sale to VM
            viewModel.onSale = onSaleLocal

            // Push category selections back to VM (top remains single)
            if let topID = selectedTopLocal,
               let topName = topCategories.first(where: { $0.id == topID })?.name {
                viewModel.selectedTopCategoryID = topID
                viewModel.selectedTopCategoryName = topName
            } else {
                viewModel.selectedTopCategoryID = nil
                viewModel.selectedTopCategoryName = nil
            }

            // Push subcategory multi-select
            viewModel.selectedSubcategoryIDs = selectedSubLocalSet
            // Clear single subcategory fields to avoid ambiguity
            if let subID = selectedSubLocal, selectedSubLocalSet.isEmpty {
                // If user left it as single and no multi-selected items, keep the single
                if let subName = subcategories.first(where: { $0.id == subID })?.name {
                    viewModel.selectedSubcategoryID = subID
                    viewModel.selectedSubcategoryName = subName
                } else {
                    viewModel.selectedSubcategoryID = nil
                    viewModel.selectedSubcategoryName = nil
                }
            } else {
                viewModel.selectedSubcategoryID = nil
                viewModel.selectedSubcategoryName = nil
            }

            // Push location selections back to VM
            if let topLocationID = selectedTopLocationLocal,
               let topLocationName = topLocations.first(where: { $0.id == topLocationID })?.name {
                viewModel.selectedTopLocationID = topLocationID
                viewModel.selectedTopLocationName = topLocationName
                lastTopLocation = topLocationID
                lastTopLocationName = topLocationName
            } else {
                viewModel.selectedTopLocationID = nil
                viewModel.selectedTopLocationName = nil
            }
            if let subLocationID = selectedSubLocationLocal,
               let subLocationName = subLocations.first(where: { $0.id == subLocationID })?.name {
                viewModel.selectedSubLocationID = subLocationID
                viewModel.selectedSubLocationName = subLocationName
                lastSubLocation = subLocationID
                lastSubLocationName = subLocationName
            } else {
                viewModel.selectedSubLocationID = nil
                viewModel.selectedSubLocationName = nil
            }

            onApply()
        }
        .sheet(isPresented: $showAgeSheet) {
            AgeVerificationSheet(
                onOver18: {
                    ageVerified18Plus = true
                    if pendingRestrictedToggle {
                        handleRestrictedToggleChange(true)
                    }
                    pendingRestrictedToggle = false
                    showAgeSheet = false
                },
                onUnder18: {
                    pendingRestrictedToggle = false
                    showAgeSheet = false
                }
            )
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Networking for categories

    private func decodeCategoryDictionary(_ data: Data) throws -> [CategoryItem] {
        struct DTO: Decodable { let id: Int; let name: String }
        return try JSONDecoder().decode([DTO].self, from: data).map { CategoryItem(id: $0.id, name: $0.name) }
    }

    @MainActor
    private func setTopLoading(_ loading: Bool) { isLoadingTopCats = loading }
    @MainActor
    private func setSubLoading(_ loading: Bool) { isLoadingSubCats = loading }

    private func loadTopCategories() async {
        setTopLoading(true)
        defer { setTopLoading(false) }
        let components = URLComponents.apiEndpoint("categories")
        guard let url = components.url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            let items = try decodeCategoryDictionary(data)

            await MainActor.run {
                self.topCategories = items
                // Cache top categories in the VM
                viewModel.cachedTopCategories = items
                // Keep VM cache in sync with restrictedOnly for Adult presence
                if viewModel.restrictedOnly {
                    if !viewModel.cachedTopCategories.contains(adultCategory) {
                        viewModel.cachedTopCategories.append(adultCategory)
                    }
                } else {
                    if viewModel.cachedTopCategories.contains(adultCategory) {
                        viewModel.cachedTopCategories.removeAll { $0 == adultCategory }
                    }
                }
                // If restricted is ON, append Adult at the end (keep last) BEFORE validation locally
                if viewModel.restrictedOnly {
                    appendAdultCategoryIfNeeded()
                } else {
                    removeAdultCategoryIfPresent()
                }
                // Validate current top selection; if missing, clear it and dependent sub
                if let selTop = selectedTopLocal, !topCategories.contains(where: { $0.id == selTop }) {
                    selectedTopLocal = nil
                    selectedSubLocal = nil
                    selectedSubLocalSet = []
                    subcategories = []
                    viewModel.selectedTopCategoryID = nil
                    viewModel.selectedTopCategoryName = nil
                    viewModel.selectedSubcategoryID = nil
                    viewModel.selectedSubcategoryName = nil
                    viewModel.selectedSubcategoryIDs = []
                }
            }
        } catch {
            // Silent failure
        }
    }

    private func loadSubcategories(parentID: Int) async {
        setSubLoading(true)
        defer { setSubLoading(false) }
        let components = URLComponents.apiEndpoint(
            "categories",
            queryItems: [URLQueryItem(name: "id", value: String(parentID))]
        )
        guard let url = components.url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            let items = try decodeCategoryDictionary(data)
            await MainActor.run {
                self.subcategories = items
                // Cache the subcategories for this parent in the VM
                viewModel.cachedSubcategoriesByParent[parentID] = items
                // Validate current sub selections (multi + single) against the fetched list
                let validIDs = Set(items.map { $0.id })
                selectedSubLocalSet = selectedSubLocalSet.intersection(validIDs)
                if let sel = selectedSubLocal, !items.contains(where: { $0.id == sel }) {
                    selectedSubLocal = nil
                }
            }
        } catch {
            // Silent failure
        }
    }

    // MARK: - Networking for Locations

    private func decodeLocationArray(_ data: Data) throws -> [LocationItem] {
        struct DTO: Decodable { let id: Int; let name: String }
        return try JSONDecoder().decode([DTO].self, from: data).map { LocationItem(id: $0.id, name: $0.name) }
    }

    @MainActor
    private func setTopLocationLoading(_ loading: Bool) { isLoadingTopLocations = loading }
    @MainActor
    private func setSubLocationLoading(_ loading: Bool) { isLoadingSubLocations = loading }

    private func loadTopLocations() async {
        setTopLocationLoading(true)
        defer { setTopLocationLoading(false) }
        let components = URLComponents.apiEndpoint("location")
        guard let url = components.url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            let items = try decodeLocationArray(data)
            await MainActor.run {
                self.topLocations = items
            }
        } catch {
            // Silent failure
        }
    }

    private func loadSubLocations(parentID: Int) async {
        setSubLocationLoading(true)
        defer { setSubLocationLoading(false) }
        let components = URLComponents.apiEndpoint(
            "location",
            queryItems: [URLQueryItem(name: "id", value: String(parentID))]
        )
        guard let url = components.url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            let items = try decodeLocationArray(data)
            await MainActor.run {
                self.subLocations = items
            }
        } catch {
            // Silent failure
        }
    }

    // MARK: - Apply/Clear helpers

    private func markDirtyIfNeeded() {
        let f = fromText.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = toText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentFrom = priceFrom.map(String.init) ?? ""
        let currentTo = priceTo.map(String.init) ?? ""
        isDirty = (f != currentFrom) || (t != currentTo) || isDirty
    }
    
    private func applyFilters() {
        func digitsOnly(_ s: String) -> String {
            s.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.map(String.init).joined()
        }
        let fDigits = digitsOnly(fromText.trimmingCharacters(in: .whitespacesAndNewlines))
        let tDigits = digitsOnly(toText.trimmingCharacters(in: .whitespacesAndNewlines))
        priceFrom = Int(fDigits)
        priceTo   = Int(tDigits)
        fromText = fDigits
        toText   = tDigits
        isDirty = false
    }
    
    private func appendAdultCategoryIfNeeded() {
        if !topCategories.contains(adultCategory) {
            topCategories.append(adultCategory)
        }
    }

    private func removeAdultCategoryIfPresent() {
        if topCategories.contains(adultCategory) {
            topCategories.removeAll { $0 == adultCategory }
        }
    }

    private func handleRestrictedToggleChange(_ enabled: Bool) {
        viewModel.restrictedOnly = enabled
        if enabled {
            // Keep local list and VM cache in sync with Adult present
            appendAdultCategoryIfNeeded()
            if !viewModel.cachedTopCategories.contains(adultCategory) {
                viewModel.cachedTopCategories.append(adultCategory)
            }
            if selectedTopLocal != adultCategory.id {
                selectedTopLocal = adultCategory.id
                selectedSubLocal = nil
                selectedSubLocalSet = []
                subcategories = []
                Task { await loadSubcategories(parentID: adultCategory.id) }
            }
            viewModel.selectedTopCategoryID = adultCategory.id
            viewModel.selectedTopCategoryName = adultCategory.name
            viewModel.selectedSubcategoryID = nil
            viewModel.selectedSubcategoryName = nil
            viewModel.selectedSubcategoryIDs = []
        } else {
            // Remove Adult from both local list and VM cache
            if selectedTopLocal == adultCategory.id {
                selectedTopLocal = nil
                selectedSubLocal = nil
                selectedSubLocalSet = []
                subcategories = []
            }
            removeAdultCategoryIfPresent()
            if viewModel.cachedTopCategories.contains(adultCategory) {
                viewModel.cachedTopCategories.removeAll { $0 == adultCategory }
            }
            if viewModel.selectedTopCategoryID == adultCategory.id {
                viewModel.selectedTopCategoryID = nil
                viewModel.selectedTopCategoryName = nil
            }
            viewModel.selectedSubcategoryID = nil
            viewModel.selectedSubcategoryName = nil
            viewModel.selectedSubcategoryIDs = []
        }
        isDirty = true
    }
}

// MARK: - Age Verification Sheet UI
struct AgeVerificationSheet: View {
    var onOver18: () -> Void
    var onUnder18: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Age Verification")
                .font(.headline)
                .padding(.top, 22)

            Text("To view adult/restricted results, you must confirm you are at least 18 years old.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 10) {
                Button(action: onOver18) {
                    HStack { Spacer(); Text("I am over 18").bold(); Spacer() }
                        .padding(14)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .cancel, action: onUnder18) {
                    HStack { Spacer(); Text("I am under 18"); Spacer() }
                        .padding(14)
                }
                .buttonStyle(.bordered)

                Button(role: .cancel, action: onUnder18) {
                    HStack { Spacer(); Text("Cancel"); Spacer() }
                        .padding(14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Spacer(minLength: 8)
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Checkbox Toggle Style

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                configuration.label
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

