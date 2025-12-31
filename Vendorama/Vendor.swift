import Foundation

// Helper to decode either an Int or a numeric String into Int?
private enum FlexibleInt {
    static func decode(_ container: KeyedDecodingContainer<Vendor.CodingKeys>, forKey key: Vendor.CodingKeys) throws -> Int? {
        // Try Int first
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }
        // Then try String and coerce
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            let trimmed = stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            return Int(trimmed)
        }
        // If key missing or null
        return nil
    }
}

struct Vendor: Decodable, Hashable {
    // Nested category object
    struct Category: Decodable, Hashable {
        let id: Int?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Flexible decode for id
            if let intValue = try? c.decodeIfPresent(Int.self, forKey: .id) {
                id = intValue
            } else if let stringValue = try? c.decodeIfPresent(String.self, forKey: .id) {
                let trimmed = stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                id = Int(trimmed)
            } else {
                id = nil
            }
            name = try c.decodeIfPresent(String.self, forKey: .name)
        }
    }

    // Core links and identity
    let name: String?
    let url: String?
    let thumb: String?
    let username: String?
    let vendor_id: Int?
    let products: Int?
    let licence: Int?

    // Contact/location
    let address1: String?
    let address2: String?
    let city: String?
    let postcode: String?
    let email: String?
    let phone: String?

    // Profile
    let description: String?
    let category_id: Int?
    let nzbn: Int?
    let gender: Int?
    let restricted: Int?
    
    // product
    let views: Int?
    let clicks: Int?
    let likes: Int?
    let categories: [Category]?
    
    enum CodingKeys: String, CodingKey {
        case name
        case url
        case thumb
        case username
        case vendor_id
        case products
        case licence
        case address1
        case address2
        case city
        case postcode
        case email
        case phone
        case description
        case category_id
        case nzbn
        case gender
        case restricted
        case views
        case clicks
        case likes
        case categories
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        // Strings
        name = try c.decodeIfPresent(String.self, forKey: .name)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        thumb = try c.decodeIfPresent(String.self, forKey: .thumb)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        address1 = try c.decodeIfPresent(String.self, forKey: .address1)
        address2 = try c.decodeIfPresent(String.self, forKey: .address2)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        postcode = try c.decodeIfPresent(String.self, forKey: .postcode)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        description = try c.decodeIfPresent(String.self, forKey: .description)

        // Flexible Int-or-String fields
        vendor_id = try FlexibleInt.decode(c, forKey: .vendor_id)
        products = try FlexibleInt.decode(c, forKey: .products)
        licence = try FlexibleInt.decode(c, forKey: .licence)
        category_id = try FlexibleInt.decode(c, forKey: .category_id)
        nzbn = try FlexibleInt.decode(c, forKey: .nzbn)
        gender = try FlexibleInt.decode(c, forKey: .gender)
        restricted = try FlexibleInt.decode(c, forKey: .restricted)
        views = try FlexibleInt.decode(c, forKey: .views)
        clicks = try FlexibleInt.decode(c, forKey: .clicks)
        likes = try FlexibleInt.decode(c, forKey: .likes)
        // categories array of objects
        categories = try c.decodeIfPresent([Category].self, forKey: .categories)
    }
}

