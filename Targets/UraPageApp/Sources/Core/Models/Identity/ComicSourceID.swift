import Foundation

/// 标识一个编译期漫画源，是持久化、路由、缓存与下载身份的一部分。
///
/// - `rawValue` 一经发布不可修改，也不能用显示名称替代来源标识。
/// - `CaseIterable` 供 composition 阶段校验所有编译期来源均已注册，
///   不代表运行时动态插件列表。
enum ComicSourceID: String, CaseIterable, Hashable, Codable, Sendable {
    case jm
    case bika
    case shenshi
}
