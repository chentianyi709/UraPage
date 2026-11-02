import Foundation

/// 来源凭证的编解码记录：公共 Keychain 层不理解字段语义，只保存编码后的数据。
///
/// 每个来源声明自己的 `Codable` 凭证结构，用本类型承载“缺数据返回 nil、
/// 写入替换、删除幂等”的同一语义，不再各写一份 `*CredentialStore` 外壳。
struct SourceCredentialRecord<Value: Codable & Sendable>: Sendable {
    private let sourceID: ComicSourceID
    private let storage = SourceCredentialStore()

    /// 绑定来源标识；Keychain account 由该标识隔离。
    init(sourceID: ComicSourceID) {
        self.sourceID = sourceID
    }

    /// 读取并解码凭证；尚未保存时返回 `nil`。
    func load() throws -> Value? {
        guard let data = try storage.load(for: sourceID) else {
            return nil
        }

        return try JSONDecoder().decode(Value.self, from: data)
    }

    /// 编码并替换当前凭证。
    func save(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        try storage.save(data, for: sourceID)
    }

    /// 删除凭证；尚未保存时同样视为成功。
    func delete() throws {
        try storage.delete(for: sourceID)
    }
}
