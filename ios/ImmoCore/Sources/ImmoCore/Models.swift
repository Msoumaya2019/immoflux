import Foundation

public struct ListingSource: Codable, Hashable {
    public var source: String
    public var url: String
    public var sourceListingId: String
}
public struct PricePoint: Codable, Hashable {
    public var date: Date
    public var price: Double
}
public struct Listing: Codable, Identifiable, Hashable {
    public var id: String
    public var source: String
    public var sourceListingId: String
    public var title: String
    public var url: String
    public var imageUrl: String?
    public var imageUrls: [String]
    public var price: Double?
    public var surface: Double?
    public var rooms: Int?
    public var bedrooms: Int?
    public var landSurface: Double?
    public var propertyType: String
    public var transactionType: String
    public var city: String
    public var postalCode: String
    public var latitude: Double?
    public var longitude: Double?
    public var description: String
    public var agency: String
    public var publicationDate: Date?
    public var firstSeenDate: Date
    public var lastSeenDate: Date
    public var pricePerSquareMeter: Double?
    public var previousPrice: Double?
    public var priceChange: Double?
    public var priceChangedAt: Date?
    public var priceHistory: [PricePoint]
    public var isFavorite: Bool
    public var isHidden: Bool
    public var memberIds: [String]
    public var sources: [ListingSource]
    public var allIDs: Set<String> { Set(memberIds + [id]) }
    public var typeLabel: String { ["house": "Maison", "apartment": "Appartement", "pavilion": "Pavillon"][propertyType] ?? propertyType }
    public func isNew(at date: Date = Date()) -> Bool {
        (0..<86400).contains(date.timeIntervalSince(firstSeenDate))
    }
}
public struct Coverage: Codable {
    public var city: String
    public var postalCode: String?
    public var transactionType: String
    public var minRooms: Int
}
public struct ListingsEnvelope: Codable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var lastSuccessfulFetch: Date?
    public var coverage: [Coverage]
    public var listings: [Listing]
}
public struct Provider: Codable, Identifiable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var status: String
    public var message: String
    public var lastRun: Date
    public var lastSuccess: Date?
    public var count: Int
    public var statusLabel: String {
        ["ok": "Fonctionnel", "partial": "Collecte partielle", "error": "Erreur", "disabled": "Désactivé", "unavailable": "Non disponible"][status] ?? status
    }
}
public struct ProvidersEnvelope: Codable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var providers: [Provider]
}
public enum JSONCoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
public enum ListingSort: String, Codable, CaseIterable {
    case recent = "Plus récentes", ascending = "Prix croissant", descending = "Prix décroissant"
    case surface = "Surface", perMeter = "Prix/m²", drop = "Dernière baisse de prix"
}
public struct SearchPreferences: Codable, Equatable {
    public var city = "Montmagny"
    public var postalCode = "95360"
    public var radiusKm: Double = 0
    public var centerLatitude: Double? = 48.973
    public var centerLongitude: Double? = 2.346
    public var transaction = "sale"
    public var minRooms = 4
    public var minBedrooms = 0
    public var minPrice: Double = 0
    public var maxPrice: Double = 0
    public var minSurface: Double = 0
    public var minLand: Double = 0
    public var types: Set<String> = ["house", "apartment", "pavilion"]
    public var disabledSources: Set<String> = []
    public var keywords = ""
    public var sort: ListingSort = .recent
    public init() {}
    public func matches(_ item: Listing) -> Bool {
        if radiusKm > 0 {
            guard let lat = centerLatitude, let lon = centerLongitude,
                  let ilat = item.latitude, let ilon = item.longitude,
                  Self.distance(lat, lon, ilat, ilon) <= radiusKm else { return false }
        } else {
            guard Self.fold(item.city) == Self.fold(city.trimmingCharacters(in: .whitespacesAndNewlines)),
                  postalCode.isEmpty || item.postalCode == postalCode else { return false }
        }
        guard item.transactionType == transaction, types.contains(item.propertyType),
              (item.rooms ?? 0) >= minRooms, (item.bedrooms ?? 0) >= minBedrooms,
              (minPrice == 0 || (item.price ?? -1) >= minPrice),
              (maxPrice == 0 || (item.price ?? .infinity) <= maxPrice),
              (item.surface ?? 0) >= minSurface, (item.landSurface ?? 0) >= minLand else { return false }
        let sourceIDs = item.sources.isEmpty ? [item.source] : item.sources.map(\.source)
        guard sourceIDs.contains(where: { !disabledSources.contains($0) }) else { return false }
        let text = Self.fold(item.title + " " + item.description)
        return keywords.split(whereSeparator: \.isWhitespace).allSatisfy { text.contains(Self.fold(String($0))) }
    }
    public func sorted(_ items: [Listing]) -> [Listing] {
        items.sorted { a, b in
            switch sort {
            case .recent: return (a.publicationDate ?? a.firstSeenDate) > (b.publicationDate ?? b.firstSeenDate)
            case .ascending: return (a.price ?? .infinity) < (b.price ?? .infinity)
            case .descending: return (a.price ?? -1) > (b.price ?? -1)
            case .surface: return (a.surface ?? -1) > (b.surface ?? -1)
            case .perMeter: return (a.pricePerSquareMeter ?? .infinity) < (b.pricePerSquareMeter ?? .infinity)
            case .drop:
                let ad = (a.priceChange ?? 0) < 0 ? a.priceChangedAt : nil
                let bd = (b.priceChange ?? 0) < 0 ? b.priceChangedAt : nil
                return (ad ?? .distantPast) > (bd ?? .distantPast)
            }
        }
    }
    public static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((lat2-lat1)*r/2), 2) + cos(lat1*r)*cos(lat2*r)*pow(sin((lon2-lon1)*r/2), 2)
        return 6371 * 2 * atan2(sqrt(a), sqrt(max(0, 1-a)))
    }
}
