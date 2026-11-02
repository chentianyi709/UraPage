import Foundation

/// 绅士网页登录接口的 JSON 外壳。
///
/// 服务端响应头声明为 HTML，但正文实际是 JSON；App 只读取登录是否成功，
/// 网页弹层使用的 `html` 字段由 `Decodable` 自动忽略。
struct ShenshiLoginDTO: Decodable, Sendable {
    let ret: Bool
}
