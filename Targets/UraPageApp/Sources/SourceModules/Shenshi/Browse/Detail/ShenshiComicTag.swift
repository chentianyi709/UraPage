/// 保存绅士详情标签的显示名称和安全在线导航 key。
struct ShenshiComicTag: Codable, Hashable, Sendable {
    let name: String

    /// Source Client 可以直接解释、且不包含 Host 的稳定导航 key。
    let navigationKey: String

    /// 用网页解析结果创建经过协议校验的标签。
    init?(name: String, navigationKey: String) {
        guard !name.isEmpty,
              navigationKey.firstMatch(of: #/^albums-index-tag-[^/?#\\\r\n]+\.html$/#) != nil
        else {
            return nil
        }

        self.name = name
        self.navigationKey = navigationKey
    }
}
