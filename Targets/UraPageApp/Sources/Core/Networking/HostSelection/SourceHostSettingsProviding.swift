import Foundation

/// 来源设置页需要的服务器线路能力。
///
/// 三家来源的 Services 已经提供同名方法；协议只固定设置页的接线，
/// 让页面不必重复写两份闭包，也不要求来源知道 `SourceHostSettingsModel` 的内部形状。
protocol SourceHostSettingsProviding: Sendable {
    func hostSelectionSnapshot() async throws -> SourceHostSelectionSnapshot

    func selectHost(baseURL: URL) async throws -> SourceHostSelectionSnapshot
}
