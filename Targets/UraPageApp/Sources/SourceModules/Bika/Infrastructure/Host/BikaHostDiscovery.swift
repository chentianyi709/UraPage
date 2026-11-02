import Foundation

/// 哔咔 Host 发现：候选来自代码内置的固定地址，不做远程发现。
///
/// 与动态来源一样交给公共 `SourceHostProvider` 管理固定偏好与进程内状态，
/// 从而复用同一套选择/切换语义。候选顺序：默认 go2778 地址（CDN中转）、官方地址（官方直连）。
enum BikaHostDiscovery {
    /// 返回内置候选。
    static func discoverCandidates() -> [SourceHostCandidate] {
        BikaConfiguration.Host.orderedCandidates
    }
}
