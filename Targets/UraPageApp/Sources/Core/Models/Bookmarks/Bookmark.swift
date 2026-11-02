import CryptoKit
import Foundation

/// 一条可收藏的检索维度：来源 + 维度 + 展示名 + 来源私有身份。
///
/// `payload` 是来源自己编码的 typed 值（哔咔分类、绅士标签等）：公共层不认识它的结构，
/// 只负责原样保存，跳转时交回对应来源解码。这样既不用把来源字段搬进公共模型，
/// 也不会像裸字符串那样丢掉导航所需的身份（例如绅士标签的 `navigationKey`）。
struct Bookmark: Hashable, Sendable {
    let sourceID: ComicSourceID
    let kind: BookmarkKind
    let displayName: String
    let payload: Data

    /// 稳定身份键（来源＋维度＋展示名）。
    ///
    /// 初始化时算一次：按钮与列表在每次渲染都会读它，没必要每次重算摘要。
    /// 用户能识别的身份就是这三个字段，payload 只用于跳转、不参与判断；
    /// 重复收藏同一条时覆盖成最新的 payload。实际数据中不会出现同名但来源私有类型不同的条目，
    /// 因此不需要把类型或 ID 纳入身份键。
    /// 算法必须保持稳定：已存书签的 key 与页面新建书签的 key 一旦不一致，
    /// 会出现「已收藏却显示未收藏」、重复插入或删不掉旧行。
    let identityKey: String

    /// 用来源 typed 值创建条目。
    ///
    /// 参与收藏的值都是只含字符串／数字的 `Codable` 结构，编码失败属于程序错误。
    init(sourceID: ComicSourceID, kind: BookmarkKind, displayName: String, value: some Encodable) {
        guard let payload = try? JSONEncoder().encode(value) else {
            preconditionFailure("书签身份编码失败：\(sourceID.rawValue)/\(kind.rawValue)")
        }

        self.init(sourceID: sourceID, kind: kind, displayName: displayName, payload: payload)
    }

    /// 用已保存的 payload 还原条目（持久化层读取用）。
    init(sourceID: ComicSourceID, kind: BookmarkKind, displayName: String, payload: Data) {
        self.sourceID = sourceID
        self.kind = kind
        self.displayName = displayName
        self.payload = payload
        identityKey = SourceDigest.hex(
            SHA256.hash(
                data: IdentityKeyEncoder.v1([sourceID.rawValue, kind.rawValue, displayName]),
            ),
        )
    }

    /// 把 payload 还原为来源 typed 值；失败说明收藏来自旧版本或已损坏。
    func decoded<Value: Decodable>(_ type: Value.Type = Value.self) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: payload)
        } catch {
            throw ComicSourceError.invalidIdentity
        }
    }
}
