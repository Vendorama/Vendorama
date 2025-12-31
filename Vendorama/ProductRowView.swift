import SwiftUI
import SDWebImageSwiftUI

#if canImport(SafariServices)
import SafariServices

struct ProductSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No-op
    }
}
#endif

struct ProductRowView: View {
    let product: Product
    @ObservedObject var viewModel: SearchViewModel
    @State private var imageLoaded = false
    @Environment(\.dismissSearch) private var dismissSearch
    @EnvironmentObject private var favorites: FavoritesStore

    // Callback to trigger navigation from parent
    var onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Image -> navigate on tap
            if let imageURL = apiURL(product.image) {
                Button(action: { onSelect() }) {
                    WebImage(url: imageURL)
                        .onSuccess { _, _, _ in
                            DispatchQueue.main.async {
                                imageLoaded = true
                            }
                        }
                        .resizable()
                        .scaledToFit()
                        .opacity(imageLoaded ? 1.0 : 0.0)
                        .animation(.easeIn(duration: 0.2), value: imageLoaded)
                        .frame(maxWidth: .infinity, maxHeight: 180)
                        .cornerRadius(10)
                        .clipped()
                        .overlay(
                            Group {
                                if !imageLoaded {
                                    ProgressView()
                                        .frame(width: 180, height: 180)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }

            // Price row -> navigate on tap
            Button(action: { onSelect() }) {
                PriceView(price: product.price, sale_price: product.sale_price)
                    .font(.body)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)

            // Name -> navigate on tap
            Button(action: { onSelect() }) {
                Text("\(product.name)")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .tint(.primary)
                    .background(Color(.systemBackground))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)

            if(viewModel.searchType != "vendor") {
                 Button {
                    dismissSearch()
                    viewModel.searchVendor(to: product.vendor_id)
                 } label: {
                     Image("store")
                         .resizable()
                         .scaledToFit()
                         .foregroundStyle(.secondary)
                         .frame(height: 9)
                         .opacity(0.6)
                         .offset(x:3)
                     Text("\(product.vendor_name)")
                 }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 4)
                .lineLimit(1)
            }
             
            Button("+ more like this") {
                dismissSearch()
                // Prefer product_id for the related endpoint
                viewModel.searchRelated(to: product)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .padding(.top, 10)
        .padding(.bottom, 10)
        .overlay(
            HStack {
                Spacer()
                VStack {
                    Button {
                        favorites.toggleFavorite(product.id)
                    } label: {
                        Image(systemName: favorites.isFavorite(product.id) ? "heart.fill" : "heart")
                            .foregroundStyle(favorites.isFavorite(product.id) ? .purple : .secondary)
                            .padding(6)
                            .background(favorites.isFavorite(product.id) ? Color(.systemBackground).opacity(1.0) : Color(.systemBackground).opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(6)
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            .offset(x:0, y:10)
        )
    }
}

struct PriceView: View {
    var price: String
    var sale_price: String

    var body: some View {
        HStack {
            if(!sale_price.isEmpty) {
                Text(sale_price)
                    .foregroundStyle(.red)
                    .strikethrough()
            }
            Text(price)
                .foregroundStyle(.black)
                .bold()
        }
    }
}

struct ProductRowViewRelated: View {
    let product: Product
    @ObservedObject var viewModel: SearchViewModel
    @State private var imageLoaded = false
    @Environment(\.dismissSearch) private var dismissSearch
    @EnvironmentObject private var favorites: FavoritesStore

    // Callback to trigger navigation from parent
    var onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            // Image -> navigate on tap
            if let imageURL = apiURL(product.image) {
                Button(action: { onSelect() }) {
                    WebImage(url: imageURL)
                        .onSuccess { _, _, _ in
                            DispatchQueue.main.async {
                                imageLoaded = true
                            }
                        }
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .frame(width: 120, height: 120, alignment: .center)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                        .cornerRadius(80.0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 80.0)
                                .stroke(Color.white, lineWidth: 10)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .offset(x:30)
            }

            // Favorite button under image for related layout
            HStack {
                Spacer()
                Button(action: {
                    favorites.toggleFavorite(product.id)
                }) {
                    Image(systemName: favorites.isFavorite(product.id) ? "heart.fill" : "heart")
                        .foregroundStyle(favorites.isFavorite(product.id) ? .purple : .secondary)
                        .imageScale(.medium)
                        .accessibilityLabel(favorites.isFavorite(product.id) ? "Remove from favourites" : "Add to favourites")
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
                
            Text("showing more like this")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 0)
                .italic()
                .frame(maxWidth: .infinity, alignment: .center)
            
            Button(action: {
                dismissSearch()
                viewModel.searchVendor(to: product.vendor_id)
            }) {
                HStack {
                    Text("view all from \n**\(product.vendor_name)**")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 2)
            .padding(.bottom, 2)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
    }
}

struct ProductRowViewVendor: View {
    let product: Product
    @ObservedObject var viewModel: SearchViewModel
    @State private var imageLoaded = false
    @State private var showSafari = false
    @Environment(\.dismissSearch) private var dismissSearch
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        VStack(alignment: .leading) {
            if let imageURL = apiURL(product.image) {
                Button(action: { showSafari = true }) {
                    WebImage(url: imageURL)
                        .onSuccess { _, _, _ in
                            DispatchQueue.main.async {
                                imageLoaded = true
                            }
                        }
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .frame(width: 120, height: 120, alignment: .center)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                        .cornerRadius(80.0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 80.0)
                                .stroke(Color.white, lineWidth: 10)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .offset(x:30)
            }

            // Favorite button under image for vendor layout
            HStack {
                Spacer()
                Button(action: {
                    favorites.toggleFavorite(product.id)
                }) {
                    Image(systemName: favorites.isFavorite(product.id) ? "heart.fill" : "heart")
                        .foregroundStyle(favorites.isFavorite(product.id) ? .purple : .secondary)
                        .imageScale(.medium)
                        .accessibilityLabel(favorites.isFavorite(product.id) ? "Remove from favourites" : "Add to favourites")
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
            
            let vendorURL = (URL(string: product.url)?.host) ?? " "

            if let thisurl = URL(string: product.url) {
                Button {
                    showSafari = true
                } label: {
                    Text("showing all from \n\(product.vendor_name)\n\(vendorURL)")
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 11)
                        .padding(.bottom, 22)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal)
                .sheet(isPresented: $showSafari, content: {
                    ProductSafariView(url: thisurl)
                })
            }
        }
    }
}

#if DEBUG
private extension Product {
    static var previewItem: Product {
        Product(
            name: "Preview Sneaker Low-Cut - Cloud White / Core Black",
            price: "$129.00",
            sale_price: "$159.00",
            image: "https://picsum.photos/seed/row/400/400",
            url: "https://example.com/item",
            product_id: "prev-001",
            vendor_id: "vendor-xyz",
            vendor_name: "Preview Vendor",
            summary: "Preview Summary",
            suburb: "Preview Suburb",
            vc: "Preview VC"
        )
    }

    static var previewVendorItem: Product {
        Product(
            name: "Vendor Exclusive Hoodie",
            price: "$89.00",
            sale_price: "$109.00",
            image: "https://picsum.photos/seed/vendor/400/400",
            url: "https://example.com/vendor-item",
            product_id: "prev-002",
            vendor_id: "vendor-xyz",
            vendor_name: "Preview Vendor",
            summary: "Preview Summary",
            suburb: "Preview Suburb",
            vc: "Preview vc"
        )
    }
}

private extension SearchViewModel {
    static func preview(searchType: String = "search") -> SearchViewModel {
        let vm = SearchViewModel()
        vm.searchType = searchType
        vm.query = "preview"
        return vm
    }
}

struct ProductRowView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                ProductRowView(product: .previewItem, viewModel: .preview(searchType: "search"), onSelect: {})
                    .padding()
            }
            .previewDisplayName("Row - Light")

            NavigationView {
                ProductRowView(product: .previewItem, viewModel: .preview(searchType: "search"), onSelect: {})
                    .padding()
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Row - Dark")

            NavigationView {
                ProductRowViewRelated(product: .previewItem, viewModel: .preview(searchType: "related"), onSelect: {})
                    .padding()
            }
            .previewDisplayName("Related Row")

            NavigationView {
                ProductRowViewVendor(product: .previewVendorItem, viewModel: .preview(searchType: "vendor"))
                    .padding()
            }
            .previewDisplayName("Vendor Row")
        }
        .environmentObject(FavoritesStore())
    }
}
#endif

