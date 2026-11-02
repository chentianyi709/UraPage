import Foundation

/// 描述解密后与 API Host 选择相关的最小响应字段。
///
/// 候选以 `jm3_Server`（每项 `[域名, 线路名]`）为准，它包含网页显示的全部线路；
/// `Server` 作为没有 `jm3_Server` 时的回退。
struct JMComicHostPayload: Decodable {
    let servers: [String]

    /// 每项为 `[域名, 线路名]`；缺失时回退到 `Server`。
    let jm3Server: [[String]]?

    private enum CodingKeys: String, CodingKey {
        case servers = "Server"
        case jm3Server = "jm3_Server"
    }
}
