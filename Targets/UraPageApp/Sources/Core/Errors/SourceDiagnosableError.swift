/// 来源内部错误可提供不含敏感关联值的诊断名，供日志使用。
///
/// 实现只返回错误类别名（可包含安全的数值码，如 HTTP/业务码），
/// 不得包含响应正文、凭证、Cookie 或私有 Host。
protocol SourceDiagnosableError: Error {
    var diagnosticName: String { get }
}
