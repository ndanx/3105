import Foundation

struct AdminLicense: Identifiable, Equatable {
    let id: String
    let key: String
    let name: String?
    let status: String?
    let expiry: Date?
}

enum AdminLicenseError: LocalizedError {
    case invalidToken
    case invalidConfiguration
    case requestFailed(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .invalidToken: return "El token administrador no es válido o no tiene permisos suficientes."
        case .invalidConfiguration: return "Falta configurar la política de licencias."
        case .requestFailed(let status): return "Keygen respondió con el código \(status)."
        case .malformedResponse: return "Keygen devolvió una respuesta inesperada."
        }
    }
}

enum AdminLicenseClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func list(token: String) async throws -> [AdminLicense] {
        let data = try await request(path: "/licenses", method: "GET", token: token)
        return parseMany(data)
    }

    static func create(name: String?, policyID: String, token: String) async throws -> AdminLicense {
        guard !policyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AdminLicenseError.invalidConfiguration
        }
        var relationships: [String: Any] = [
            "policy": ["data": ["type": "policies", "id": policyID]]
        ]
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var attributes: [String: Any] = [:]
        if !trimmedName.isEmpty { attributes["name"] = trimmedName }
        let body: [String: Any] = [
            "data": [
                "type": "licenses",
                "attributes": attributes,
                "relationships": relationships
            ]
        ]
        let data = try await request(path: "/licenses", method: "POST", token: token, body: body)
        guard let result = parseOne(data) else { throw AdminLicenseError.malformedResponse }
        return result
    }

    static func suspend(id: String, token: String) async throws {
        _ = try await request(path: "/licenses/\(safeID(id))/actions/suspend", method: "POST", token: token)
    }

    static func reinstate(id: String, token: String) async throws {
        _ = try await request(path: "/licenses/\(safeID(id))/actions/reinstate", method: "POST", token: token)
    }

    static func revoke(id: String, token: String) async throws {
        _ = try await request(path: "/licenses/\(safeID(id))/actions/revoke", method: "DELETE", token: token)
    }

    private static func safeID(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }

    private static func request(
        path: String,
        method: String,
        token: String,
        body: [String: Any]? = nil
    ) async throws -> Data {
        guard let url = URL(string: LicenseConfig.baseURL + path) else {
            throw AdminLicenseError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 { throw AdminLicenseError.invalidToken }
            throw AdminLicenseError.requestFailed(status)
        }
        return data
    }

    private static func parseMany(_ data: Data) -> [AdminLicense] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["data"] as? [[String: Any]] else { return [] }
        return values.compactMap(parse)
    }

    private static func parseOne(_ data: Data) -> AdminLicense? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["data"] as? [String: Any] else { return nil }
        return parse(value)
    }

    private static func parse(_ value: [String: Any]) -> AdminLicense? {
        guard let id = value["id"] as? String,
              let attributes = value["attributes"] as? [String: Any] else { return nil }
        let expiry: Date?
        if let raw = attributes["expiry"] as? String {
            expiry = try? decoder.date(from: raw)
        } else {
            expiry = nil
        }
        return AdminLicense(
            id: id,
            key: attributes["key"] as? String ?? "",
            name: attributes["name"] as? String,
            status: attributes["status"] as? String,
            expiry: expiry
        )
    }
}
