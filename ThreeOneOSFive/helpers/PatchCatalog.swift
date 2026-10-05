import Foundation

/// One patch published in the remote catalog (catalog.json).
struct PatchCatalogEntry: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String?
    let version: String?
    let size: Int64?
    let url: URL
    /// Optional. Package UUID of the .3105 file, used to detect it as installed.
    let packageID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, name, version, size, url, packageID
        case summary = "description"
    }
}

/// Decodes an element without failing the whole array when one entry is malformed.
private struct LossyEntry: Decodable {
    let value: PatchCatalogEntry?

    init(from decoder: Decoder) throws {
        value = try? PatchCatalogEntry(from: decoder)
    }
}

private struct PatchCatalogFile: Decodable {
    let patches: [LossyEntry]
}

enum PatchCatalogService {
    /// Public URL of the catalog.json file (raw file of the fork on GitHub).
        static let catalogURL = URL(string: "https://raw.githubusercontent.com/ndanx/3105/base-1.1.1/catalog/catalog.json")!
    static func fetch() async throws -> [PatchCatalogEntry] {
        var request = URLRequest(
            url: catalogURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let file = try JSONDecoder().decode(PatchCatalogFile.self, from: data)
        var seen = Set<String>()
        return file.patches
            .compactMap(\.value)
            .filter { PatchImportRoute.validatedRemoteURL($0.url) != nil }
            .filter { seen.insert($0.id).inserted }
    }
}

@MainActor
final class PatchCatalogStore: ObservableObject {
    @Published private(set) var entries: [PatchCatalogEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    @Published private(set) var hasLoaded = false
    /// Catalog entry id -> package UUID of the patch downloaded from it.
    @Published private var installedMap: [String: String]

    private static let installedKey = "patch.catalog.installed"

    init() {
        installedMap = UserDefaults.standard.dictionary(forKey: Self.installedKey) as? [String: String] ?? [:]
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            entries = try await PatchCatalogService.fetch()
            loadFailed = false
        } catch {
            if Task.isCancelled { return }
            loadFailed = true
        }
    }

    func isInstalled(_ entry: PatchCatalogEntry, in items: [PatchLibraryItem]) -> Bool {
        if let packageID = entry.packageID, items.contains(where: { $0.id == packageID }) {
            return true
        }
        if let mapped = installedMap[entry.id].flatMap(UUID.init(uuidString:)),
           items.contains(where: { $0.id == mapped }) {
            return true
        }
        return items.contains {
            $0.project?.name.caseInsensitiveCompare(entry.name) == .orderedSame
        }
    }

    func recordInstall(entryID: String, packageID: UUID) {
        installedMap[entryID] = packageID.uuidString
        UserDefaults.standard.set(installedMap, forKey: Self.installedKey)
    }
}
