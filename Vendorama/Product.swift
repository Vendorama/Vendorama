import Foundation

struct Product: Identifiable, Equatable, Hashable, Codable {
    var id: String { vendor_id + "." + product_id }
    let name: String
    let price: String
    let sale_price: String
    let image: String
    let url: String
    let product_id: String
    let vendor_id: String
    let vendor_name: String
    let summary: String
    let suburb: String
    let vc: String

    enum CodingKeys: String, CodingKey {
        case name
        case price = "price"
        case sale_price = "sale_price"
        case image = "image"
        case url = "url"
        case product_id = "product_id"
        case vendor_id = "vendor_id"
        case vendor_name = "vendor_name"
        case summary = "summary"
        case suburb = "suburb"
        case vc = "vc"
    }

    init(
        name: String,
        price: String,
        sale_price: String,
        image: String,
        url: String,
        product_id: String,
        vendor_id: String,
        vendor_name: String,
        summary: String,
        suburb: String,
        vc: String
    ) {
        self.name = name
        self.price = price
        self.sale_price = sale_price
        self.image = image
        self.url = url
        self.product_id = product_id
        self.vendor_id = vendor_id
        self.vendor_name = vendor_name
        self.summary = summary
        self.suburb = suburb
        self.vc = vc
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        price = try c.decode(String.self, forKey: .price)
        sale_price = try c.decode(String.self, forKey: .sale_price)
        image = try c.decode(String.self, forKey: .image)
        url = try c.decode(String.self, forKey: .url)

        // product_id and vendor_id are always integers in the payload
        // Decode as Int and convert to String to keep the rest of the app unchanged.
        if let pidInt = try? c.decode(Int.self, forKey: .product_id) {
            product_id = String(pidInt)
        } else {
            // Fallback if server ever sends string
            product_id = try c.decode(String.self, forKey: .product_id)
        }
        if let vidInt = try? c.decode(Int.self, forKey: .vendor_id) {
            vendor_id = String(vidInt)
        } else {
            vendor_id = try c.decode(String.self, forKey: .vendor_id)
        }
        if let vcInt = try? c.decode(Int.self, forKey: .vc) {
            vc = String(vcInt)
        } else {
            vc = try c.decode(String.self, forKey: .vc)
        }

        vendor_name = try c.decode(String.self, forKey: .vendor_name)
        summary = try c.decode(String.self, forKey: .summary)
        suburb = try c.decode(String.self, forKey: .suburb)
    }
}

