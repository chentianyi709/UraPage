
/// 保存单页失败的安全类别，不暴露来源 URL、响应或底层库对象。
nonisolated enum ReaderPageFailure: Error, Equatable, Sendable {
    case networkUnavailable
    case timedOut
    case rateLimited
    case authenticationRequired
    case invalidPayload
    case localAssetMissing
    case localAssetCorrupted
    case identityMismatch
    case sourceUnavailable

    /// 返回单页占位按钮使用的可操作文案。
    var retryTitle: String {
        switch self {
        case .networkUnavailable:
            "网络不可用，重新加载"
        case .timedOut:
            "请求超时，重新加载"
        case .rateLimited:
            "请求过于频繁，重新加载"
        case .authenticationRequired:
            "需要验证账号，重新加载"
        case .invalidPayload:
            "图片解析失败，重新加载"
        case .localAssetMissing:
            "本地图片未下载，重新读取"
        case .localAssetCorrupted:
            "本地图片损坏，重新读取"
        case .identityMismatch:
            "页面身份失效，重新加载"
        case .sourceUnavailable:
            "页面加载失败，重新加载"
        }
    }

    /// 离线读取本地资产失败时的占位文案；重试无法恢复，因此不提供重试操作。
    var localFailureTitle: String {
        switch self {
        case .localAssetMissing:
            "本地图片缺失"
        case .localAssetCorrupted, .invalidPayload:
            "本地图片损坏"
        default:
            "本地图片不可用"
        }
    }

    /// 把来源公开错误收敛为 Reader 节点可以安全保存的类别。
    static func map(_ error: any Error, fallback: ReaderPageFailure) -> ReaderPageFailure {
        if let failure = error as? ReaderPageFailure {
            return failure
        }
        if let assetError = error as? DownloadAssetError {
            switch assetError {
            case .missingPage:
                return .localAssetMissing
            case .unsafeRelativePath, .corruptedManifest, .corruptedAsset, .assetLeased:
                return .localAssetCorrupted
            }
        }
        guard let sourceError = error as? ComicSourceError else {
            return fallback
        }

        switch sourceError {
        case .invalidIdentity:
            return .identityMismatch
        case .authenticationRequired:
            return .authenticationRequired
        case .networkUnavailable:
            return .networkUnavailable
        case .timedOut:
            return .timedOut
        case .rateLimited:
            return .rateLimited
        case .invalidResponse:
            return .invalidPayload
        case .serverRejected:
            return .sourceUnavailable
        }
    }
}
