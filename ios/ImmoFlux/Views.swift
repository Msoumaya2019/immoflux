import SwiftUI
import ImmoCore
import MapKit

func euros(_ value: Double?) -> String {
    guard let value else { return "Prix non communiqué" }
    return value.formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0)))
}
func metric(_ value: Double?) -> String {
    value.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " m²" } ?? "—"
}
struct RootView: View {
    var body: some View {
        TabView {
            FeedView(mode: .listings).tabItem { Label("Annonces", systemImage: "house") }
            FeedView(mode: .favorites).tabItem { Label("Favoris", systemImage: "heart") }
            FeedView(mode: .search).tabItem { Label("Recherche", systemImage: "magnifyingglass") }
            SettingsView().tabItem { Label("Réglages", systemImage: "gearshape") }
        }.tint(.teal)
    }
}
enum FeedMode { case listings, favorites, search }
struct FeedView: View {
    @EnvironmentObject var store: Store
    let mode: FeedMode
    @State private var quick = "Tous"
    @State private var filters = false
    var items: [Listing] {
        let base = mode == .favorites ? store.savedFavorites : store.filtered
        return base.filter {
            switch quick {
            case "Maisons": return ["house", "pavilion"].contains($0.propertyType)
            case "Appartements": return $0.propertyType == "apartment"
            case "Favoris": return store.isFavorite($0)
            default: return true
            }
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header
                    if mode != .favorites {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(["Tous", "Maisons", "Appartements", "Favoris"], id: \.self) { title in
                                    Button(title) { quick = title }
                                        .buttonStyle(.bordered).tint(quick == title ? .teal : .secondary)
                                        .accessibilityAddTraits(quick == title ? .isSelected : [])
                                }
                            }
                        }
                    }
                    if items.isEmpty {
                        ContentUnavailableView(mode == .favorites ? "Vos favoris vous attendent" : "Aucun bien à afficher",
                            systemImage: mode == .favorites ? "heart" : "house",
                            description: Text(mode == .favorites ? "Touchez le cœur d’une annonce pour la conserver ici." : "Vérifiez les filtres, la couverture et l’état des sources dans les réglages."))
                    }
                    ForEach(items) { item in
                        ListingCard(item: item)
                    }
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(mode == .favorites ? "Favoris" : (mode == .search ? "Recherche" : "Biens à \(store.preferences.city)"))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Task { await store.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.disabled(store.refreshing).accessibilityLabel("Actualiser les annonces")
                    Button { filters = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Filtres")
                }
            }
            .searchable(text: $store.preferences.keywords, prompt: "Garage, jardin, terrasse, DPE B…")
            .refreshable { await store.refresh() }
            .sheet(isPresented: $filters) { NavigationStack { FiltersView() } }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(items.count) annonce\(items.count == 1 ? "" : "s")").font(.headline)
                Spacer()
                if store.refreshing { ProgressView().accessibilityLabel("Actualisation") }
                Menu {
                    Picker("Tri", selection: $store.preferences.sort) {
                        ForEach(ListingSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: { Label("Trier", systemImage: "arrow.up.arrow.down") }
            }
            if let date = store.envelope?.lastSuccessfulFetch {
                Text("Collecte \(date, style: .relative)").font(.caption).foregroundStyle(.secondary)
            } else { Text("Aucune collecte réussie à ce jour").font(.caption).foregroundStyle(.secondary) }
            if let message = store.message {
                Label(message, systemImage: "wifi.exclamationmark").font(.callout).foregroundStyle(.orange)
            }
            if let message = store.coverageMessage, mode != .favorites {
                Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct ListingCard: View {
    @EnvironmentObject var store: Store
    let item: Listing
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink { DetailView(item: item) } label: {
                ListingPhoto(url: item.imageUrl).frame(height: 220).clipped()
                    .overlay(alignment: .topLeading) {
                        if item.isNew() {
                            Text("NOUVEAU").font(.caption.bold()).padding(8)
                                .background(.teal, in: Capsule()).foregroundStyle(.white).padding(12)
                        }
                    }
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    NavigationLink { DetailView(item: item) } label: {
                        Text(euros(item.price)).font(.title2.bold()).foregroundStyle(.primary)
                    }.buttonStyle(.plain)
                    Spacer()
                    Button { store.toggleFavorite(item) } label: {
                        Image(systemName: store.isFavorite(item) ? "heart.fill" : "heart")
                            .font(.title2).foregroundStyle(store.isFavorite(item) ? .pink : .secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.plain).accessibilityLabel(store.isFavorite(item) ? "Retirer des favoris" : "Ajouter aux favoris")
                }
                Text("\(item.typeLabel) · \(item.rooms.map(String.init) ?? "—") pièces · \(metric(item.surface))")
                    .font(.subheadline)
                Text("\(item.city) \(item.postalCode)").foregroundStyle(.secondary)
                HStack {
                    if let price = item.pricePerSquareMeter { Text("\(euros(price))/m²") }
                    Spacer()
                    if let change = item.priceChange, change < 0 {
                        Label(euros(change), systemImage: "chart.line.downtrend.xyaxis").foregroundStyle(.green)
                    }
                }.font(.caption)
                Text("Sources : \(item.sources.map(\.source).joined(separator: " · "))")
                    .font(.caption).foregroundStyle(.secondary)
                if Date().timeIntervalSince(item.lastSeenDate) > 86400 {
                    Text("Dernière observation : \(item.lastSeenDate, style: .date)").font(.caption).foregroundStyle(.orange)
                }
            }.padding()
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contextMenu {
            Button { store.toggleHidden(item) } label: {
                Label(store.isHidden(item) ? "Restaurer cette annonce" : "Masquer cette annonce", systemImage: "eye.slash")
            }
        }
    }
}
struct DetailView: View {
    @EnvironmentObject var store: Store
    let item: Listing
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TabView {
                    if item.imageUrls.isEmpty { ListingPhoto(url: nil) }
                    ForEach(item.imageUrls, id: \.self) { ListingPhoto(url: $0) }
                }.tabViewStyle(.page).frame(height: 290)
                VStack(alignment: .leading, spacing: 16) {
                    Text(euros(item.price)).font(.largeTitle.bold())
                    Text(item.title).font(.title3.weight(.semibold))
                    if let old = item.previousPrice, let change = item.priceChange, change < 0 {
                        Label("Ancien prix : \(euros(old)) · baisse de \(euros(-change))", systemImage: "chart.line.downtrend.xyaxis")
                            .foregroundStyle(.green)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                        detailRow("Surface", metric(item.surface))
                        detailRow("Pièces / chambres", "\(item.rooms.map(String.init) ?? "—") / \(item.bedrooms.map(String.init) ?? "—")")
                        detailRow("Prix au m²", item.pricePerSquareMeter.map { euros($0) } ?? "—")
                        detailRow("Terrain", metric(item.landSurface))
                        detailRow("Type", item.typeLabel)
                        detailRow("Ville", "\(item.city) \(item.postalCode)")
                    }
                    Divider()
                    Text("À propos de ce bien").font(.headline)
                    Text(item.description.isEmpty ? "Description non disponible." : item.description).textSelection(.enabled)
                    if !item.agency.isEmpty { Text("Agence : \(item.agency)") }
                    if let date = item.publicationDate { Text("Publié le \(date, style: .date)") }
                    Text("Première détection : \(item.firstSeenDate, style: .date)").font(.footnote)
                    Text("Dernière observation : \(item.lastSeenDate, style: .date)").font(.footnote)
                    if item.priceHistory.count > 1 {
                        DisclosureGroup("Historique des prix") {
                            ForEach(item.priceHistory, id: \.date) { point in
                                HStack { Text(point.date, style: .date); Spacer(); Text(euros(point.price)) }.font(.footnote)
                            }
                        }
                    }
                    ForEach(item.sources, id: \.url) { source in
                        if let url = URL(string: source.url), url.scheme == "https" {
                            Link("Voir sur \(source.source)", destination: url)
                        }
                    }
                    Button(store.isHidden(item) ? "Restaurer cette annonce" : "Masquer cette annonce") { store.toggleHidden(item) }
                        .foregroundStyle(.secondary)
                }.padding(.horizontal)
            }.padding(.bottom, 24)
        }
        .navigationTitle(item.typeLabel).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { store.toggleFavorite(item) } label: {
                Image(systemName: store.isFavorite(item) ? "heart.fill" : "heart")
            }.accessibilityLabel("Modifier le favori")
        }
        .safeAreaInset(edge: .bottom) {
            if let url = URL(string: item.url), url.scheme == "https" {
                Link(destination: url) {
                    Text("VOIR L’ANNONCE ORIGINALE").font(.headline).frame(maxWidth: .infinity).padding(8)
                }.buttonStyle(.borderedProminent).padding().background(.regularMaterial)
            }
        }
    }
    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow { Text(title).foregroundStyle(.secondary); Text(value) }
    }
}
struct FiltersView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var body: some View {
        Form {
            LocationFields()
            Section("Votre recherche") {
                Picker("Transaction", selection: $store.preferences.transaction) {
                    Text("Vente").tag("sale"); Text("Location").tag("rent")
                }
                Stepper("Pièces minimum : \(store.preferences.minRooms)", value: $store.preferences.minRooms, in: 0...20)
                Stepper("Chambres minimum : \(store.preferences.minBedrooms)", value: $store.preferences.minBedrooms, in: 0...20)
                NumericField(title: "Prix minimum (€)", value: $store.preferences.minPrice)
                NumericField(title: "Prix maximum (€)", value: $store.preferences.maxPrice)
                NumericField(title: "Surface minimum (m²)", value: $store.preferences.minSurface)
                NumericField(title: "Terrain minimum (m²)", value: $store.preferences.minLand)
            }
            Section("Types de biens") {
                ForEach(["house", "apartment", "pavilion"], id: \.self) { kind in
                    Toggle(["house": "Maison", "apartment": "Appartement", "pavilion": "Pavillon"][kind]!, isOn: Binding(
                        get: { store.preferences.types.contains(kind) },
                        set: { if $0 { store.preferences.types.insert(kind) } else { store.preferences.types.remove(kind) } }))
                }
            }
            Section {
                Button("Réinitialiser les filtres", role: .destructive) { store.preferences = SearchPreferences() }
                Text("Les préférences sont enregistrées immédiatement. 0 signifie aucune limite. Les filtres s’appliquent aux données collectées par le backend.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Filtres")
            .toolbar { Button("Afficher") { dismiss(); Task { await store.refresh() } } }
    }
}
struct NumericField: View {
    let title: String
    @Binding var value: Double
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: $value, format: .number).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(minWidth: 70)
        }.onChange(of: value) { _, new in if new < 0 { value = 0 } }
    }
}
struct LocationFields: View {
    @EnvironmentObject var store: Store
    @State private var candidates: [MKMapItem] = []
    @State private var searching = false
    @State private var locationMessage: String?
    var body: some View {
        Section("Localisation") {
            TextField("Ville", text: Binding(get: { store.preferences.city }, set: { city in
                    store.preferences.city = city
                    store.preferences.centerLatitude = nil; store.preferences.centerLongitude = nil
                    store.preferences.postalCode = ""
                }))
            TextField("Code postal", text: $store.preferences.postalCode).keyboardType(.numberPad)
            Button(searching ? "Recherche…" : "Rechercher les codes postaux") { Task { await lookup() } }.disabled(searching)
            ForEach(Array(candidates.enumerated()), id: \.offset) { _, item in
                Button("\(item.placemark.locality ?? item.name ?? "Ville") · \(item.placemark.postalCode ?? "Code non fourni")") {
                    store.preferences.postalCode = item.placemark.postalCode ?? store.preferences.postalCode
                    store.preferences.centerLatitude = item.placemark.coordinate.latitude
                    store.preferences.centerLongitude = item.placemark.coordinate.longitude
                    candidates = []
                }
            }
            NumericField(title: "Rayon (km)", value: $store.preferences.radiusKm)
            if let locationMessage { Text(locationMessage).font(.caption).foregroundStyle(.secondary) }
            if store.preferences.radiusKm > 0 && store.preferences.centerLatitude == nil {
                Text("Sélectionnez une ville dans les résultats pour définir le centre du rayon.").font(.caption).foregroundStyle(.orange)
            }
        }
    }
    @MainActor private func lookup() async {
        searching = true; defer { searching = false }
        let city = store.preferences.city
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = city + ", France"
        request.resultTypes = .address
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard city == store.preferences.city else { return }
            candidates = response.mapItems.filter { $0.placemark.isoCountryCode == "FR" }
            locationMessage = "Choisissez un résultat. Si le code souhaité manque, saisissez-le manuellement."
        } catch { locationMessage = "Recherche de ville indisponible. Saisissez le code postal manuellement." }
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        NavigationStack {
            Form {
                LocationFields()
                Section("Critères principaux") {
                    Stepper("Pièces minimum : \(store.preferences.minRooms)", value: $store.preferences.minRooms, in: 0...20)
                    NumericField(title: "Surface minimum (m²)", value: $store.preferences.minSurface)
                    NumericField(title: "Prix maximum (€)", value: $store.preferences.maxPrice)
                    NavigationLink("Tous les filtres") { FiltersView() }
                    Button("Actualiser la recherche") { Task { await store.refresh() } }.disabled(store.refreshing)
                }
                Section("Sources affichées") {
                    if store.providers.isEmpty { Text("État des sources non chargé.") }
                    ForEach(store.providers) { provider in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(provider.name, isOn: Binding(
                                get: { !store.preferences.disabledSources.contains(provider.id) },
                                set: { if $0 { store.preferences.disabledSources.remove(provider.id) } else { store.preferences.disabledSources.insert(provider.id) } }))
                            Label(provider.statusLabel, systemImage: provider.status == "ok" ? "checkmark.circle.fill" : "info.circle")
                                .font(.caption).foregroundStyle(provider.status == "ok" ? .green : .secondary)
                            Text(provider.message).font(.caption).foregroundStyle(.secondary)
                            Text("État vérifié : \(provider.lastRun, style: .date) à \(provider.lastRun, style: .time)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text("Ces interrupteurs filtrent votre flux. L’activation de la collecte se fait dans config/providers.json.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Données") {
                    TextField("URL HTTPS de l’API", text: $store.apiURL).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if let date = store.checkedAt { Text("Dernière connexion : \(date, style: .date), \(date, style: .time)") }
                    if let date = store.envelope?.generatedAt { Text("Génération backend : \(date, style: .date), \(date, style: .time)") }
                    if let date = store.envelope?.lastSuccessfulFetch { Text("Dernière collecte : \(date, style: .date), \(date, style: .time)") }
                    if let message = store.message { Text(message).foregroundStyle(.orange) }
                    NavigationLink("Annonces masquées") {
                        List(store.allSaved.filter(store.isHidden)) { item in
                            HStack { Text(item.title); Spacer(); Button("Restaurer") { store.toggleHidden(item) } }
                        }.navigationTitle("Annonces masquées")
                    }
                }
                Section("ImmoFlux") {
                    Text("À chaque ouverture, l’application recharge le dernier JSON publié. La collecte des sites suit le planning du backend et n’est pas déclenchée par l’iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Réglages")
        }
    }
}
