import SwiftUI
import ImmoCore

struct APIConfig: Codable {
    var apiBaseURL: String
    var fallbackBaseURL: String
    static var bundled: APIConfig {
        guard let url = Bundle.main.url(forResource: "AppConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(APIConfig.self, from: data)
        else { return .init(apiBaseURL: "", fallbackBaseURL: "") }
        return config
    }
}
struct LocalSnapshot: Codable {
    var envelope: ListingsEnvelope?
    var retained: [Listing]
    var providers: [Provider]
    var favorites: Set<String>
    var hidden: Set<String>
    var checkedAt: Date?
}
enum APIError: LocalizedError {
    case configuration, response, schema
    var errorDescription: String? {
        switch self {
        case .configuration: return "Configurez une URL HTTPS publique dans les réglages."
        case .response: return "Données distantes indisponibles. Le cache local reste accessible."
        case .schema: return "Format d’API incompatible. Le cache local est conservé."
        }
    }
}
@MainActor final class Store: ObservableObject {
    @Published var preferences: SearchPreferences { didSet { savePreferences() } }
    @Published var apiURL: String { didSet { UserDefaults.standard.set(apiURL, forKey: "apiURL") } }
    @Published private(set) var envelope: ListingsEnvelope?
    @Published private(set) var providers: [Provider] = []
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var retained: [Listing] = []
    @Published private(set) var checkedAt: Date?
    @Published private(set) var refreshing = false
    @Published var message: String?
    private let cacheURL: URL
    private let config = APIConfig.bundled
    init() {
        preferences = UserDefaults.standard.data(forKey: "preferences").flatMap { try? JSONCoding.decoder().decode(SearchPreferences.self, from: $0) } ?? SearchPreferences()
        apiURL = UserDefaults.standard.string(forKey: "apiURL") ?? APIConfig.bundled.apiBaseURL
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImmoFlux")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheURL = directory.appendingPathComponent("snapshot-v1.json")
        if let data = try? Data(contentsOf: cacheURL), let cache = try? JSONCoding.decoder().decode(LocalSnapshot.self, from: data) {
            envelope = cache.envelope; retained = cache.retained; providers = cache.providers
            favorites = cache.favorites; hidden = cache.hidden; checkedAt = cache.checkedAt
        }
    }
    var listings: [Listing] { envelope?.listings ?? [] }
    var allSaved: [Listing] {
        let currentIDs = Set(listings.flatMap { Array($0.allIDs) })
        return listings + retained.filter { $0.allIDs.isDisjoint(with: currentIDs) }
    }
    func isFavorite(_ item: Listing) -> Bool { !favorites.isDisjoint(with: item.allIDs) }
    func isHidden(_ item: Listing) -> Bool { !hidden.isDisjoint(with: item.allIDs) }
    func toggleFavorite(_ item: Listing) {
        if isFavorite(item) { favorites.subtract(item.allIDs) } else { favorites.formUnion(item.allIDs) }
        retainSelections(); persist()
    }
    func toggleHidden(_ item: Listing) {
        if isHidden(item) { hidden.subtract(item.allIDs) } else { hidden.formUnion(item.allIDs) }
        retainSelections(); persist()
    }
    func retainSelections() {
        retained = allSaved.filter { isFavorite($0) || isHidden($0) }
    }
    var filtered: [Listing] { preferences.sorted(listings.filter { !isHidden($0) && preferences.matches($0) }) }
    var savedFavorites: [Listing] { preferences.sorted(allSaved.filter(isFavorite)) }
    var coverageMessage: String? {
        guard let envelope else { return nil }
        if preferences.radiusKm > 0 {
            return "Rayon appliqué aux annonces déjà collectées avec coordonnées. Il n’étend pas la collecte du backend."
        }
        let covered = envelope.coverage.contains {
            SearchPreferences.fold($0.city) == SearchPreferences.fold(preferences.city)
            && ($0.postalCode == nil || $0.postalCode == "" || $0.postalCode == preferences.postalCode)
            && $0.transactionType == preferences.transactionType && preferences.minRooms >= $0.minRooms
        }
        return covered ? nil : "Recherche hors couverture du backend. Ajoutez cette ville, ce code postal ou cette transaction dans config/searches.json."
    }
    func savePreferences() {
        if let data = try? JSONCoding.encoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "preferences") }
    }
    func persist() {
        do {
            let cache = LocalSnapshot(envelope: envelope, retained: retained, providers: providers, favorites: favorites, hidden: hidden, checkedAt: checkedAt)
            try JSONCoding.encoder().encode(cache).write(to: cacheURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch { message = "Impossible d’enregistrer le cache local : \(error.localizedDescription)" }
    }
    func fetch<T: Decodable>(_ type: T.Type, base: String, file: String) async throws -> T {
        guard let baseURL = URL(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil else { throw APIError.configuration }
        var request = URLRequest(url: baseURL.appendingPathComponent(file), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https", data.count <= 20_000_000 else { throw APIError.response }
        return try JSONCoding.decoder().decode(type, from: data)
    }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        message = nil
        var latestError: Error = APIError.configuration
        let bases = [apiURL, config.fallbackBaseURL].filter { !$0.isEmpty }
        for (index, base) in bases.enumerated() {
            do {
                let result = try await fetch(ListingsEnvelope.self, base: base, file: "listings.json")
                guard result.schemaVersion == 1 else { throw APIError.schema }
                retainSelections()
                for item in result.listings {
                    if isFavorite(item) { favorites.formUnion(item.allIDs) }
                    if isHidden(item) { hidden.formUnion(item.allIDs) }
                }
                envelope = result
                checkedAt = Date()
                do {
                    let status = try await fetch(ProvidersEnvelope.self, base: base, file: "providers.json")
                    guard status.schemaVersion == 1 else { throw APIError.schema }
                    providers = status.providers
                } catch { message = "Annonces chargées ; état des sources indisponible ou ancien." }
                if index > 0 { message = "Source principale indisponible. Données chargées depuis l’URL de secours." }
                persist()
                return
            } catch { latestError = error }
        }
        message = latestError.localizedDescription
    }
}
