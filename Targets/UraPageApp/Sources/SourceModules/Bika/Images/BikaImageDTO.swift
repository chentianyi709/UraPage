import ReerCodable

/// 解码哔咔普通图片 locator 共同使用的文件服务字段。
@Decodable
struct BikaImageDTO: Decodable, ReerCodableDelegate, Sendable {
    /// 图片文件服务地址；映射层据此组合完整直连地址。
    let fileServer: String

    /// 图片在文件服务上的相对路径。
    let path: String
}
