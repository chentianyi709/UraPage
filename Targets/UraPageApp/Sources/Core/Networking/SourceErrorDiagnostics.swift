import Alamofire
import Foundation

#if DEBUG
    /// 网络重试、Client 恢复与 Services 收尾共用的脱敏错误摘要，仅编译进 Debug。
    /// 只输出类型、阶段与数值代码，不读取错误描述、URL、Header 或响应正文。
    enum SourceErrorDiagnostics {
        static func summary(for error: any Error) -> String {
            var values = ["internal=\(diagnosticName(for: error))"]

            if let alamofireError = error as? AFError {
                values.append("stage=\(stage(of: alamofireError))")
                if let responseCode = alamofireError.responseCode {
                    values.append("status=\(responseCode)")
                }
            }

            if let urlError = SourceNetworkErrorMapper.underlyingURLError(in: error) {
                values.append("urlCode=\(urlError.code.rawValue)")
            }

            return values.joined(separator: "，")
        }

        /// 来源内部错误优先使用其安全诊断名；其它错误仅输出类型名，避免展开关联值。
        private static func diagnosticName(for error: any Error) -> String {
            if let diagnosable = error as? any SourceDiagnosableError {
                return diagnosable.diagnosticName
            }
            return String(reflecting: type(of: error))
        }

        /// 稳定阶段名便于区分请求构造、网络传输与响应处理失败。
        private static func stage(of error: AFError) -> String {
            if error.isInvalidURLError
                || error.isParameterEncodingError
                || error.isParameterEncoderError
                || error.isCreateURLRequestError {
                return "requestConstruction"
            }
            if error.isRequestAdaptationError {
                return "requestAdaptation"
            }
            if error.isSessionTaskError {
                return "transport"
            }
            if error.isResponseValidationError {
                return "responseValidation"
            }
            if error.isResponseSerializationError {
                return "responseSerialization"
            }
            if error.isRequestRetryError {
                return "retry"
            }
            if error.isSessionDeinitializedError || error.isSessionInvalidatedError {
                return "session"
            }
            return "other"
        }
    }
#endif
