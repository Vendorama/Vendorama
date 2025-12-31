import SwiftUI
import SDWebImageSwiftUI

struct ProductDetailView: View {
    let product: Product
    @ObservedObject var viewModel: SearchViewModel

    // When presented inside a container (like the Favorites sheet),
    // the presenter can provide a way to dismiss that container.
    var onRequestDismissContainer: (() -> Void)? = nil

    @State private var showSafari = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissSearch) private var dismissSearch
    @EnvironmentObject private var favorites: FavoritesStore

    // Resolved category title after lazy loading (optional)
    @State private var resolvedCategoryTitle: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Full-width image, maintaining aspect ratio
                if let imageURL = apiURL(product.image) {
                    ZStack {
                        Color(.systemBackground)
                            .frame(maxWidth: .infinity, maxHeight: 300)

                        WebImage(url: imageURL)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300, alignment: .center)
                            .clipped()
                    }
                }

                // Title / price
                VStack(alignment: .leading, spacing: 8) {
                    
                    PriceView(price: product.price, sale_price: product.sale_price)
                        .font(.system(size: 26))
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    Text(product.name)
                        .font(.system(size: 16))
                        .lineLimit(6)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .tint(.primary)
                        .background(Color(.systemBackground))

                    if !product.vendor_name.isEmpty {
                        Button(action: {
                            onRequestDismissContainer?()
                            dismiss()
                            DispatchQueue.main.async {
                                dismissSearch()
                                viewModel.searchVendor(to: product.vendor_id)
                            }
                        }) {
                            Image("store")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.secondary)
                                .frame(height: 14)
                                .opacity(0.5)
                                .offset(x:1, y:1)
                            Text("\(product.vendor_name)")
                                .font(.subheadline)
                                .padding(.top, 2)
                            
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(.secondary)
                        
                        if product.suburb != "" {
                            Text(product.suburb)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }

                    if !product.summary.isEmpty {
                        Text("\(product.summary)")
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                            .padding(.bottom, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                // Open product URL in-app using SafariView
                if let url = URL(string: product.url) {
                    Button {
                        showSafari = true
                    } label: {
                        Text("View on website")
                            .frame(maxWidth: .infinity)
                            .padding(6)
                        /*
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(10)
                         */
                    }
                    .font(.body.weight(.semibold))
                    //.frame(maxWidth: .infinity)
                    //.padding()
                    //
                    .buttonStyle(.glassProminent)
                    //
                    .glassEffect(.regular.interactive())
                    .padding(.horizontal)
                    .sheet(isPresented: $showSafari) {
                        SafariView(url: url)
                    }
                }
                
                Button("+ more like this") {
                    onRequestDismissContainer?()
                    dismiss()
                    DispatchQueue.main.async {
                        dismissSearch()
                        viewModel.searchRelated(to: product)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

                // Category button (lazy loads names if cache is empty)
                if product.vc != "" {
                    let fallbackTitle: String = {
                        guard let id = Int(product.vc) else { return "" }
                        if let info = viewModel.categoryInfo(for: id) {
                            if let subID = info.subID, subID > 999 {
                                print()
                                let parent = cleanCategoryName(info.parentName) ?? ""
                                let sub = cleanCategoryName(info.subName) ?? ""
                                if sub != "" {
                                    return "\(parent) › \(sub)"
                                }
                                return "not found \(parent) › \(sub) \(subID) "
                            } else {
                                return cleanCategoryName(info.parentName) ?? ""
                            }
                        } else {
                            return ""
                        }
                    }()

                    let titleToShow = resolvedCategoryTitle ?? fallbackTitle

                    Button(titleToShow) {
                        onRequestDismissContainer?()
                        dismiss()
                        DispatchQueue.main.async {
                            dismissSearch()
                            
                            // Strict category-only: clear all previous state/filters first
                            viewModel.resetFilters()
                            
                            // Apply the destination category
                            if let id = Int(product.vc) {
                                if id < 999 {
                                    viewModel.selectedTopCategoryID = id
                                    viewModel.selectedSubcategoryID = nil
                                    if let info = viewModel.categoryInfo(for: id) {
                                        viewModel.selectedTopCategoryName = info.parentName
                                        viewModel.selectedSubcategoryName = nil
                                    } else {
                                        viewModel.selectedTopCategoryName = nil
                                        viewModel.selectedSubcategoryName = nil
                                    }
                                } else {
                                    guard let vcpid = computeParentCategoryID(from: id) else { return }
                                    viewModel.selectedTopCategoryID = vcpid
                                    viewModel.selectedSubcategoryID = id
                                    if let info = viewModel.categoryInfo(for: id) {
                                        viewModel.selectedTopCategoryName = info.parentName
                                        viewModel.selectedSubcategoryName = info.subName
                                    } else {
                                        viewModel.selectedTopCategoryName = nil
                                        viewModel.selectedSubcategoryName = nil
                                    }
                                }
                            }
                            
                            // Trigger the search with only vc set
                            viewModel.refreshFirstPage()
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .task {
                        // Lazy-load only what we need for this vc, then resolve title
                        guard let id = Int(product.vc) else { return }
                        if id < 999 {
                            await viewModel.ensureTopCategoriesLoaded()
                        } else {
                            guard let parentID = computeParentCategoryID(from: id) else { return }
                            await viewModel.ensureTopCategoriesLoaded()
                            await viewModel.ensureSubcategoriesLoaded(parentID: parentID)
                        }
                        // After loading, resolve title again from cache
                        if let info = viewModel.categoryInfo(for: id) {
                            if let subID = info.subID, subID > 999 {
                                let parent = cleanCategoryName(info.parentName) ?? ""
                                let sub = cleanCategoryName(info.subName) ?? ""
                                if sub != "" {
                                    resolvedCategoryTitle = "\(parent) › \(sub)"
                                }
                            } else {
                                resolvedCategoryTitle = cleanCategoryName(info.parentName) ?? ""
                            }
                        }
                    }
                }
                
            }

            .overlay(
                HStack {
                    Spacer()
                    VStack {
                        Button {
                            favorites.toggleFavorite(product.id)
                        } label: {
                            Image(systemName: favorites.isFavorite(product.id) ? "heart.fill" : "heart")
                                .foregroundStyle(favorites.isFavorite(product.id) ? .purple : .secondary)
                                .padding(16)
                                .background(favorites.isFavorite(product.id) ? Color(.systemBackground).opacity(1.0) : Color(.systemBackground).opacity(0.8))
                                .clipShape(Circle())
                                .offset(x:-10, y:20)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .padding(6)
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
            }
        }
        .background(Color(.systemBackground))
        .task {
            await APIRequest.sendRequest(endpoint: "product", id:  product.id)
        }
    }
}

#if DEBUG
struct ProductDetailView_Previews: PreviewProvider {
    static var sampleProduct: Product {
        Product(
            name: "Sample Product Title That Wraps Across Multiple Lines For Preview",
            price: "$129.00",
            sale_price: "$159.00",
            image: "https://picsum.photos/seed/vendorama/600/600",
            url: "https://www.example.com/product",
            product_id: "preview-001",
            vendor_id: "vendor-123",
            vendor_name: "Preview Vendor",
            summary: "Preview Summary",
            suburb: "Preview Suburb",
            vc: "1000"
        )
    }

    static var viewModel: SearchViewModel = {
        let vm = SearchViewModel()
        vm.searchType = "search"
        vm.query = "sneakers"
        return vm
    }()

    static var previews: some View {
        Group {
            NavigationView {
                ProductDetailView(product: sampleProduct, viewModel: viewModel)
            }
            .previewDisplayName("Light")

            NavigationView {
                ProductDetailView(product: sampleProduct, viewModel: viewModel)
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark")
        }
    }
}
#endif
