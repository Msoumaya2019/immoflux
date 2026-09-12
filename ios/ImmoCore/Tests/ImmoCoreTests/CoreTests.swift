import XCTest
@testable import ImmoCore

final class CoreTests: XCTestCase {
    func fixture() throws -> Listing {
        let json = #"""
        {"id":"one","source":"test","sourceListingId":"1","title":"Maison avec jardin",
        "url":"https://example.org/1","imageUrls":[],"price":350000,"surface":100,"rooms":5,"bedrooms":3,
        "propertyType":"house","transactionType":"sale","city":"Montmagny","postalCode":"95360",
        "description":"Garage et terrasse. DPE B.","agency":"","firstSeenDate":"2026-09-12T08:00:00Z",
        "lastSeenDate":"2026-09-12T08:00:00Z","priceHistory":[],"isFavorite":false,"isHidden":false,
        "memberIds":["one","two"],"sources":[{"source":"test","sourceListingId":"1","url":"https://example.org/1"}]}
        """#
        return try JSONCoding.decoder().decode(Listing.self, from: Data(json.utf8))
    }
    func testDefaultSearch() throws { XCTAssertTrue(SearchPreferences().matches(try fixture())) }
    func testRoomAndCityChanges() throws {
        var prefs = SearchPreferences(); prefs.minRooms = 6
        XCTAssertFalse(prefs.matches(try fixture()))
        prefs.minRooms = 4; prefs.city = "Paris"
        XCTAssertFalse(prefs.matches(try fixture()))
    }
    func testKeywordSearch() throws {
        var prefs = SearchPreferences(); prefs.keywords = "GARAGE terrasse"
        XCTAssertTrue(prefs.matches(try fixture()))
        prefs.keywords = "piscine"
        XCTAssertFalse(prefs.matches(try fixture()))
    }
    func testNewBadgeExpiry() throws {
        let listing = try fixture()
        XCTAssertTrue(listing.isNew(at: listing.firstSeenDate.addingTimeInterval(100)))
        XCTAssertFalse(listing.isNew(at: listing.firstSeenDate.addingTimeInterval(86400)))
        XCTAssertFalse(listing.isNew(at: listing.firstSeenDate.addingTimeInterval(-1)))
    }
    func testPreferencesRoundTrip() throws {
        var prefs = SearchPreferences(); prefs.city = "Évry"; prefs.minRooms = 7
        prefs.disabledSources = ["pap"]; prefs.maxPrice = 420000
        let data = try JSONCoding.encoder().encode(prefs)
        XCTAssertEqual(try JSONCoding.decoder().decode(SearchPreferences.self, from: data), prefs)
    }
    func testMissingPriceExcludedByBudget() throws {
        var item = try fixture(); item.price = nil
        var prefs = SearchPreferences(); prefs.maxPrice = 400000
        XCTAssertFalse(prefs.matches(item))
    }
    func testRadiusRequiresCoordinates() throws {
        var prefs = SearchPreferences(); prefs.radiusKm = 10
        var item = try fixture()
        XCTAssertFalse(prefs.matches(item))
        item.latitude = prefs.centerLatitude; item.longitude = prefs.centerLongitude
        XCTAssertTrue(prefs.matches(item))
    }
    func testHiddenSourceExclusion() throws {
        var prefs = SearchPreferences(); prefs.disabledSources = ["test"]
        XCTAssertFalse(prefs.matches(try fixture()))
    }
    func testCanonicalAliases() throws { XCTAssertEqual(try fixture().allIDs, ["one", "two"]) }
    func testSortAscendingUnknownLast() throws {
        let a = try fixture(); var b = a; b.id = "unknown"; b.price = nil
        var prefs = SearchPreferences(); prefs.sort = .ascending
        XCTAssertEqual(prefs.sorted([b, a]).map(\.id), ["one", "unknown"])
    }
    func testPublicEnvelopeContract() throws {
        // CI also decodes the actual backend output, not just a hand-written fixture.
        guard let root = ProcessInfo.processInfo.environment["IMMO_REPOSITORY"] else { return }
        let url = URL(fileURLWithPath: root).appendingPathComponent("public/listings.json")
        let envelope = try JSONCoding.decoder().decode(ListingsEnvelope.self, from: Data(contentsOf: url))
        XCTAssertEqual(envelope.schemaVersion, 1)
        let providers = URL(fileURLWithPath: root).appendingPathComponent("public/providers.json")
        XCTAssertEqual(try JSONCoding.decoder().decode(ProvidersEnvelope.self, from: Data(contentsOf: providers)).schemaVersion, 1)
    }
}
