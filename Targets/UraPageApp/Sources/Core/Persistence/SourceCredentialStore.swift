import Foundation
import Security

/// 描述来源凭证 Keychain 操作失败，不包含任何凭证正文。
enum SourceCredentialStoreError: Error, Sendable {
    /// Keychain 返回的对象无法转换为凭证二进制。
    case invalidData

    /// Security API 返回了当前操作无法处理的状态码。
    case unexpectedStatus(OSStatus)
}

/// 按漫画源隔离保存敏感凭证的最小 Keychain 存储。
///
/// 来源自行序列化凭证字段；公共层不理解字段语义，只按 `sourceID` 隔离。
/// service 取自 `SourceConfiguration.Storage`，不在此重复定义前缀。
struct SourceCredentialStore: Sendable {
    /// 当前 App 的凭证统一使用独立 Keychain service，来源 ID 作为 account。
    private let service = SourceConfiguration.Storage.sourceCredentials

    /// 创建使用当前 App 标识符命名空间的凭证存储。
    init() {}

    /// 保存某个来源已经自行序列化的凭证；已有值时直接替换。
    func save(_ data: Data, for sourceID: ComicSourceID) throws {
        var query = baseQuery(for: sourceID)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(
                baseQuery(for: sourceID) as CFDictionary,
                attributes as CFDictionary,
            )
            guard updateStatus == errSecSuccess else {
                throw SourceCredentialStoreError.unexpectedStatus(updateStatus)
            }

            return
        }

        guard status == errSecSuccess else {
            throw SourceCredentialStoreError.unexpectedStatus(status)
        }
    }

    /// 读取指定来源的凭证数据；尚未登录时返回 `nil`。
    func load(for sourceID: ComicSourceID) throws -> Data? {
        var query = baseQuery(for: sourceID)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SourceCredentialStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw SourceCredentialStoreError.invalidData
        }

        return data
    }

    /// 删除指定来源的凭证；尚未保存时同样视为成功。
    func delete(for sourceID: ComicSourceID) throws {
        let status = SecItemDelete(baseQuery(for: sourceID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SourceCredentialStoreError.unexpectedStatus(status)
        }
    }

    /// 生成只命中当前 App、当前来源凭证的 Keychain 查询。
    private func baseQuery(for sourceID: ComicSourceID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID.rawValue,
        ]
    }
}
