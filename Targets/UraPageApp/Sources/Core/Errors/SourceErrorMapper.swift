import Foundation

/// 来源内部错误声明其到公共错误的映射。
///
/// 默认映射只保留安全的服务端数值业务码，其余一律收敛为 `invalidResponse`；
/// 需要额外语义（例如鉴权失效）的来源可以覆盖 `publicError`。
/// 未遵循本协议的错误由 `SourceErrorMapper` 交给网络错误映射。
protocol SourcePublicErrorMapping: Error {
    /// 服务端明确拒绝时返回其数值业务码；默认没有。
    var serverRejectionCode: Int? { get }

    /// 到公共错误的映射；默认实现见下方扩展。
    var publicError: ComicSourceError { get }
}

extension SourcePublicErrorMapping {
    /// 默认没有业务码：含 HTML 细节或纯本地失败的来源不需要声明。
    var serverRejectionCode: Int? {
        nil
    }

    /// 默认映射：有业务码时保留业务码，否则收敛为 `invalidResponse`。
    var publicError: ComicSourceError {
        guard let serverRejectionCode else {
            return .invalidResponse
        }

        return .serverRejected(code: String(serverRejectionCode))
    }
}

/// 来源边界统一的错误映射入口。
///
/// 内部错误优先按自身声明的公共映射转换，其余（Alamofire/URLSession/未知）交给
/// `SourceNetworkErrorMapper`；已经映射过的公共错误保持不变。
enum SourceErrorMapper {
    static func map(_ error: any Error) -> any Error {
        if let mapping = error as? any SourcePublicErrorMapping {
            return mapping.publicError
        }
        return SourceNetworkErrorMapper.map(error)
    }
}
