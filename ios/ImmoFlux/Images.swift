import SwiftUI
import CryptoKit

actor ImageCache {
    static let shared = ImageCache()
    private let memory = NSCache<NSString, UIImage>()
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ListingPhotos")
    private var pending: [String: Task<Data, Error>] = [:]
    init() {
        memory.totalCostLimit = 35_000_000
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func image(for value: String) async throws -> UIImage? {
        guard let url = URL(string: value), url.scheme == "https" else { return nil }
        if let image = memory.object(forKey: value as NSString) { return image }
        let key = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(key)
        var bytes: Data?
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 604800 {
            bytes = try? Data(contentsOf: file)
        }
        if bytes == nil {
            let task: Task<Data, Error>
            if let existing = pending[value] { task = existing }
            else {
                task = Task {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          http.url?.scheme == "https", data.count < 12_000_000 else { throw APIError.response }
                    return data
                }
                pending[value] = task
            }
            defer { pending[value] = nil }
            bytes = try await task.value
            if let bytes { try? bytes.write(to: file, options: .atomic) }
            trimDisk()
        }
        guard let bytes, let image = UIImage(data: bytes) else { return nil }
        memory.setObject(image, forKey: value as NSString, cost: bytes.count)
        return image
    }
    private func trimDisk() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where size > 150_000_000 {
            try? FileManager.default.removeItem(at: entry.0); size -= entry.1
        }
    }
}
struct ListingPhoto: View {
    let url: String?
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.secondarySystemBackground)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    Image(systemName: "house.fill").font(.largeTitle).foregroundStyle(.secondary)
                        .accessibilityLabel("Photo indisponible")
                }
            }
        }
        .task(id: url) {
            image = nil
            if let url { image = try? await ImageCache.shared.image(for: url) }
        }
    }
}
