import SwiftUI
import SDWebImageSwiftUI
import MapKit
import CoreLocation
import Contacts

struct VendorDetailView: View {
    let vendor: Vendor

    // Geocoding/map state
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isGeocoding: Bool = false
    @State private var geocodeError: String?
    @State private var showSafari = false
    
    // Only use map when we have a street address (address1)
    private var hasStreetAddress: Bool {
        let addr1 = (vendor.address1 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !addr1.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 12) {
                    if let thumb = vendor.thumb, let imageURL = apiURL(thumb) {
                        WebImage(url: imageURL)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary, lineWidth: 1).opacity(0.5))
                            .shadow(color: .black.opacity(0.06), radius: 4, x: -2, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 72, height: 72)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(vendor.name ?? "Store")
                                .font(.title3.weight(.semibold))
                            if (vendor.licence ?? 0) != 0 {
                                Image(systemName: "checkmark.seal.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .offset(y: 2)
                                    .foregroundStyle(Color(.blue))
                            }
                        }
                        /*
                        if let urlStr = vendor.url, let host = URL(string: urlStr)?.host {
                            Text(host)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Link(destination: URL(string: urlStr)!) {
                                Label(host, systemImage: "")
                            }
                        }
                         */
                        if let urlStr = vendor.url, let url = URL(string: urlStr) {
                            let host = url.host ?? url.absoluteString
                            Button {
                                showSafari = true
                            } label: {
                                Text(host)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .sheet(isPresented: $showSafari) {
                                SafariView(url: url)
                            }
                        }
                         
                         
                    }
                    Spacer()
                }

                // Description
                if let desc = vendor.description, !desc.isEmpty {
                    Text(desc)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Contact
                if let email = vendor.email, !email.isEmpty {
                    Link(destination: URL(string: "mailto:\(email)")!) {
                        Label(email, systemImage: "envelope")
                    }
                }
                if let phone = vendor.phone, !phone.isEmpty {
                    Link(destination: URL(string: "tel:\(phone)")!) {
                        Label(phone, systemImage: "phone")
                    }
                }

                // Address (only if address1 present)
                let addr1 = (vendor.address1 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let addr2 = (vendor.address2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let city = (vendor.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let postcode = (vendor.postcode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                if !addr1.isEmpty {
                    let cityPostcodeLine: String = {
                        switch (city.isEmpty, postcode.isEmpty) {
                        case (false, false): return "\(city) \(postcode)"
                        case (false, true):  return city
                        case (true, false):  return postcode
                        case (true, true):   return ""
                        }
                    }()
                    let displayLines = [addr1, addr2, cityPostcodeLine].filter { !$0.isEmpty }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Address")
                            .font(.headline)
                        Text(displayLines.joined(separator: "\n"))
                            .font(.body)
                            .foregroundStyle(.secondary)

                        // Map section (only when we have street address)
                        mapSection
                    }
                }
            }
            .padding()
        }
        //.navigationTitle(vendor.name ?? "Store")
        //.navigationBarTitleDisplayMode(.inline)
        
        .formStyle(.grouped) // helps reduce the big top inset
        //.navigationBarHidden(true)
        //
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        //.background(Color(.systemGroupedBackground))
        

        
        .task {
            // Only geocode when we have a street address
            if hasStreetAddress {
                await geocodeIfNeeded()
            }
        }
    }

    // MARK: - Map section

    @ViewBuilder
    private var mapSection: some View {
        // Guard again for safety
        if !hasStreetAddress {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if isGeocoding {
                    HStack {
                        ProgressView()
                        Text("Locating on map…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if let coordinate {
                    // iOS 17+ Map API; safe for iOS 26 deployment target
                    Map(initialPosition: .region(regionFor(coordinate))) {
                        Marker(vendor.name ?? "Location", coordinate: coordinate)
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Open in Apple Maps
                    if let mapItem = mkMapItem(for: coordinate) {
                        Button {
                            mapItem.openInMaps(launchOptions: [
                                MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
                                MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
                            ])
                        } label: {
                            Label("Open in Maps", systemImage: "map")
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                    }
                } else if geocodeError != nil {
                    EmptyView()
                }
            }
        }
    }

    private func regionFor(_ coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
    }

    // MKMapItem construction using modern iOS 26 API (no MKPlacemark)
    private func mkMapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem? {
        // Build a descriptive display name for Maps
        let displayName: String = {
            let addr = formattedGeocodeAddress() ?? ""
            if let vendorName = vendor.name, !vendorName.isEmpty, !addr.isEmpty {
                return "\(vendorName) – \(addr)"
            } else if !addr.isEmpty {
                return addr
            } else {
                return vendor.name ?? "Location"
            }
        }()

        // Create a basic item; we will pass the coordinate via launchOptions when opening Maps.
        let item = MKMapItem()
        item.name = displayName

        if let phone = vendor.phone, !phone.isEmpty {
            item.phoneNumber = phone
        }
        if let urlStr = vendor.url, let url = URL(string: urlStr) {
            item.url = url
        }

        return item
    }

    // MARK: - Geocoding

    private func formattedGeocodeAddress() -> String? {
        let addr1 = (vendor.address1 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addr1.isEmpty else { return nil }
        let addr2 = (vendor.address2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let city = (vendor.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let postcode = (vendor.postcode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let cityPostcode: String? = {
            switch (city.isEmpty, postcode.isEmpty) {
            case (false, false): return "\(city) \(postcode)"
            case (false, true):  return city
            case (true, false):  return postcode
            case (true, true):   return nil
            }
        }()

        var parts: [String] = [addr1]
        if !addr2.isEmpty { parts.append(addr2) }
        if let cp = cityPostcode { parts.append(cp) }
        parts.append("New Zealand")
        return parts.joined(separator: ", ")
    }

    private func formattedAddress() -> String? {
        formattedGeocodeAddress()
    }

    // Geocode using MapKit (CLGeocoder deprecated in iOS 26)
    private func geocodeIfNeeded() async {
        guard coordinate == nil, !isGeocoding else { return }
        guard hasStreetAddress, let address = formattedAddress() else { return }

        isGeocoding = true
        geocodeError = nil
        defer { isGeocoding = false }

        // Build a local search request using the formatted address
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        // Optional: set a region bias to New Zealand for better results
        // Center roughly on NZ; adjust if you have user location/other hints
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -41.2866, longitude: 174.7762), // Wellington approx center
            span: MKCoordinateSpan(latitudeDelta: 8.0, longitudeDelta: 8.0)
        )

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            if let mapItem = response.mapItems.first {
                let coord = mapItem.location.coordinate
                await MainActor.run {
                    self.coordinate = coord
                }
            } else {
                await MainActor.run { self.geocodeError = "No results" }
            }
        } catch {
            await MainActor.run { self.geocodeError = error.localizedDescription }
        }
    }
}

// Helper for iOS 14–16 Map annotations (legacy; unused for iOS 26 target but kept if referenced elsewhere)
private struct AnnotatedPin: Identifiable {
    let id = UUID()
    let title: String
    let coordinate: CLLocationCoordinate2D
}

