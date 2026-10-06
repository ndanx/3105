import Foundation
import Security
import SwiftUI
import UIKit

// MARK: - Configuration

enum LicenseConfig {
    static let accountID = "d53a37c9-6ba0-4c30-88a3-4da2062bca51"
    static let baseURL = "https://api.keygen.sh/v1/accounts/\(accountID)"
    static let requestTimeout: TimeInterval = 15
}

// MARK: - Failures

enum LicenseFailure: Equatable {
    case offline
    case server
    case notFound
    case suspended
    case expired
    case otherDevice
    case invalid(String)

    var messageKey: String {
        switch self {
        case .offline: return "license.error.offline"
        case .server: return "license.error.server"
        case .notFound: return "license.error.not_found"
        case .suspended: return "license.error.suspended"
        case .expired: return "license.error.expired"
        case .otherDevice: return "license.error.other_device"
        case .invalid: return "license.error.invalid"
        }
    }

    var detail: String? {
        if case .invalid(let code) = self { return code }
        return nil
    }
}

struct LicenseInfo {
    let licenseID: String
    let expiry: Date?
}

// MARK: - Local storage (key + device id)

enum LicenseStorage {
    private static let service = "com.apple.mobile.MobileHouseArrest.license"
    private static let keyAccount = "license-key"
    private static let deviceAccount = "device-id"
    private static let defaultsPrefix = "license.fallback."

    static var key: String? {
        get { read(keyAccount) }
        set {
            if let newValue { write(newValue, account: keyAccount) } else { delete(keyAccount) }
        }
    }

    /// Stable per-install identifier sent to Keygen as the machine fingerprint.
    static var deviceID: String {
        if let existing = read(deviceAccount) { return existing }
        let created = UUID().uuidString
        write(created, account: deviceAccount)
        return read(deviceAccount) ?? created
    }

    // Keychain first; UserDefaults only as a fallback if the keychain refuses.
    private static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }
        return UserDefaults.standard.string(forKey: defaultsPrefix + account)
    }

    private static func write(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: defaultsPrefix + account)
        } else {
            UserDefaults.standard.set(value, forKey: defaultsPrefix + account)
        }
    }

    private static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: defaultsPrefix + account)
    }
}

// MARK: - Keygen client

enum LicenseClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = LicenseConfig.requestTimeout
        configuration.timeoutIntervalForResource = LicenseConfig.requestTimeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private struct Validation {
        let valid: Bool
        let code: String
        let licenseID: String?
        let expiry: Date?
    }

    /// Validates the key for this device. The first time a key is used on a
    /// device, the device is registered (Keygen allows one machine per key).
    static func check(key: String, deviceID: String) async -> Result<LicenseInfo, LicenseFailure> {
        let first = await validate(key: key, deviceID: deviceID)
        let validation: Validation
        switch first {
        case .failure(let failure):
            return .failure(failure)
        case .success(let value):
            validation = value
        }

        if validation.valid { return .success(info(from: validation)) }

        switch validation.code {
        case "NO_MACHINE", "NO_MACHINES", "FINGERPRINT_SCOPE_MISMATCH":
            guard let licenseID = validation.licenseID else {
                return .failure(.invalid(validation.code))
            }
            if let failure = await register(key: key, licenseID: licenseID, deviceID: deviceID) {
                return .failure(failure)
            }
            switch await validate(key: key, deviceID: deviceID) {
            case .failure(let failure):
                return .failure(failure)
            case .success(let second):
                return second.valid
                    ? .success(info(from: second))
                    : .failure(failure(forCode: second.code))
            }
        default:
            return .failure(failure(forCode: validation.code))
        }
    }

    // MARK: Requests

    private static func validate(key: String, deviceID: String) async -> Result<Validation, LicenseFailure> {
        guard let url = URL(string: LicenseConfig.baseURL + "/licenses/actions/validate-key") else {
            return .failure(.server)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "meta": ["key": key, "scope": ["fingerprint": deviceID]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let status: Int
        do {
            let (responseData, response) = try await session.data(for: request)
            data = responseData
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return .failure(.offline)
        }

        if status == 404 { return .failure(.notFound) }
        if status == 429 || status >= 500 || status == 0 { return .failure(.server) }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meta = root["meta"] as? [String: Any],
              let valid = meta["valid"] as? Bool else {
            return .failure(.invalid("HTTP \(status)"))
        }
        let code = (meta["code"] as? String) ?? "UNKNOWN"
        let licenseData = root["data"] as? [String: Any]
        let attributes = licenseData?["attributes"] as? [String: Any]
        return .success(
            Validation(
                valid: valid,
                code: code,
                licenseID: licenseData?["id"] as? String,
                expiry: (attributes?["expiry"] as? String).flatMap(parseDate)
            )
        )
    }

    /// Returns nil on success, or the failure to show.
    private static func register(key: String, licenseID: String, deviceID: String) async -> LicenseFailure? {
        guard let url = URL(string: LicenseConfig.baseURL + "/machines") else { return .server }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue("License \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "data": [
                "type": "machines",
                "attributes": [
                    "fingerprint": deviceID,
                    "platform": "iOS",
                    "name": "\(AppInfo.displayMachineName) · iOS \(AppInfo.osVersion)"
                ],
                "relationships": [
                    "license": ["data": ["type": "licenses", "id": licenseID]]
                ]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let status: Int
        do {
            let (responseData, response) = try await session.data(for: request)
            data = responseData
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return .offline
        }

        if (200..<300).contains(status) { return nil }
        if status == 429 || status >= 500 || status == 0 { return .server }

        let errors = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["errors"] as? [[String: Any]]
        let code = errors?.first?["code"] as? String ?? "HTTP \(status)"
        switch code {
        case "MACHINE_LIMIT_EXCEEDED":
            return .otherDevice
        case "FINGERPRINT_TAKEN":
            // Already registered (e.g. a retry after a dropped connection).
            return nil
        default:
            return failure(forCode: code)
        }
    }

    // MARK: Helpers

    private static func info(from validation: Validation) -> LicenseInfo {
        LicenseInfo(licenseID: validation.licenseID ?? "", expiry: validation.expiry)
    }

    private static func failure(forCode code: String) -> LicenseFailure {
        switch code {
        case "NOT_FOUND": return .notFound
        case "SUSPENDED": return .suspended
        case "EXPIRED": return .expired
        case "TOO_MANY_MACHINES", "MACHINE_LIMIT_EXCEEDED": return .otherDevice
        default: return .invalid(code)
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}

// MARK: - State

@MainActor
final class LicenseManager: ObservableObject {
    enum Status: Equatable {
        case checking
        case needsKey
        case valid
        case blocked(LicenseFailure)
    }

    @Published private(set) var status: Status = .checking
    @Published private(set) var expiry: Date?
    @Published private(set) var isWorking = false

    var isUnlocked: Bool { status == .valid }
    var hasStoredKey: Bool { LicenseStorage.key != nil }

    /// Re-checks the stored key. While the app is already unlocked the
    /// content stays visible until the answer arrives; any failure locks it.
    func revalidate() {
        guard !isWorking else { return }
        guard let key = LicenseStorage.key else {
            status = .needsKey
            return
        }
        run(key: key)
    }

    func activate(_ rawKey: String) {
        guard !isWorking else { return }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        run(key: key)
    }

    /// Forgets the key on this phone (the key stays tied to this device on the server).
    func signOut() {
        LicenseStorage.key = nil
        expiry = nil
        status = .needsKey
    }

    private func run(key: String) {
        isWorking = true
        if status != .valid { status = .checking }
        let deviceID = LicenseStorage.deviceID
        Task { [weak self] in
            let result = await LicenseClient.check(key: key, deviceID: deviceID)
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let info):
                LicenseStorage.key = key
                self.expiry = info.expiry
                self.status = .valid
                log("license: valid")
            case .failure(let failure):
                if failure == .notFound, LicenseStorage.key == key {
                    LicenseStorage.key = nil
                }
                self.expiry = nil
                self.status = .blocked(failure)
                log("license: blocked (\(failure.messageKey))")
            }
        }
    }
}
