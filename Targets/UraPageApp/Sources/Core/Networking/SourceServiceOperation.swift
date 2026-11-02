import Foundation

/// 统一执行来源 Services 的公开业务操作，并在边界处完成错误映射和脱敏日志。
///
/// 各来源在公开方法里调用本工具，避免重复实现取消透传、失败日志与映射。
/// 它只处理“一次业务操作”的收尾，不负责重试、调度或 Host 恢复。
enum SourceServiceOperation {
    /// 执行一个来源业务操作；取消不记录为失败，其余错误映射后再抛出。
    ///
    /// - Parameters:
    ///   - failureMessage: 失败日志的人类可读描述，不含敏感值；仅在失败时求值，
    ///     成功路径不会为了日志而拼接字符串。
    ///   - category: 日志分类，通常为来源或功能名。
    ///   - mapError: 该来源的错误映射器，负责先处理来源私有错误。
    ///   - operation: 实际的业务调用。
    static func run<Value: Sendable>(
        failureMessage: @autoclosure () -> String,
        category: String,
        mapError: (any Error) -> any Error = SourceErrorMapper.map,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line,
        operation: () async throws -> Value,
    ) async throws -> Value {
        do {
            return try await operation()
        } catch {
            let mappedError = mapError(error)
            if mappedError is CancellationError {
                throw CancellationError()
            }

            #if DEBUG
                AppLogger.error(
                    "\(failureMessage())，\(SourceErrorDiagnostics.summary(for: error))，public=\(String(describing: mappedError))",
                    category: category,
                    file: file,
                    function: function,
                    line: line,
                )
            #endif
            throw mappedError
        }
    }
}
