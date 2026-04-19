import Foundation
import Security

struct PairedMac: Codable, Equatable {
    var host: String
    var port: Int
    var token: String

    var baseURL: URL? {
        URL(string: "http://\(host):\(port)")
    }
}

enum PairingStore {
    private static let service = "com.ayaangazali.cactusvoice.pairing"
    private static let account = "default"

    static func load() -> PairedMac? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(PairedMac.self, from: data)
    }

    @discardableResult
    static func save(_ pairing: PairedMac) -> Bool {
        guard let data = try? JSONEncoder().encode(pairing) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func parse(qrPayload: String) -> PairedMac? {
        guard let url = URL(string: qrPayload),
              url.scheme == "cactus",
              url.host == "pair",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = comps.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let v = item.value else { return nil }
            return (item.name, v)
        })
        guard let host = dict["ip"], !host.isEmpty,
              let portStr = dict["port"], let port = Int(portStr),
              let token = dict["token"], !token.isEmpty else {
            return nil
        }
        return PairedMac(host: host, port: port, token: token)
    }
}
