/// 统一执行来源 Host 选择操作，并维持设置页面需要的公开错误边界。
enum SourceHostSelectionOperation {
    /// 保留取消和已知 Host 错误，并将其它内部失败收敛为候选地址不可用。
    static func run<Value: Sendable>(
        operation: () async throws -> Value,
    ) async throws -> Value {
        do {
            return try await operation()
        } catch {
            // 取消可能来自 Alamofire 等底层边界，统一用公共判定恢复取消语义。
            if SourceNetworkErrorMapper.isCancellation(error) {
                throw CancellationError()
            }
            if let hostError = error as? SourceHostSelectionError {
                throw hostError
            }
            throw SourceHostSelectionError.candidatesUnavailable
        }
    }
}
