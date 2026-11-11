import CryptoKit
import Foundation

/// 一条书签：来源 + 维度 + 展示名 + 来源私有身份。
///
/// `kindID` 只存维度的稳定标识（`ComicTagKind.id`）；标题与图标由来源目录在展示时解析，
/// 不在书签行里另存一份展示快照。`payload` 是来源自己编码的 typed 值（哔咔分类、绅士标签等）：
/// 公共层不认识它的结构，只负责原样保存，跳转时交回对应来源解码。
struct Bookmark: Hashable, Sendable {
    let sourceID: ComicSourceID

    /// 维度标识；发布后不可修改，书签身份键由它参与计算。
    let kindID: String

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
    init(sourceID: ComicSourceID, kind: ComicTagKind, displayName: String, value: some Encodable) {
        guard let payload = try? JSONEncoder().encode(value) else {
            preconditionFailure("书签身份编码失败：\(sourceID.rawValue)/\(kind.id)")
        }

        self.init(sourceID: sourceID, kindID: kind.id, displayName: displayName, payload: payload)
    }

    /// 用已保存的 payload 还原条目（持久化层读取用）。
    init(sourceID: ComicSourceID, kindID: String, displayName: String, payload: Data) {
        self.sourceID = sourceID
        self.kindID = kindID
        self.displayName = displayName
        self.payload = payload
        identityKey = SourceDigest.hex(
            SHA256.hash(
                data: IdentityKeyEncoder.v1([sourceID.rawValue, kindID, displayName]),
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
