import Foundation

/// 一个可选线路：请求地址 + 展示名。
///
/// 展示名只用于界面（菜单项主标题）；选择与偏好持久化**只认地址**，因此改名不会影响已保存的偏好。
struct SourceHostCandidate: Hashable, Sendable {
    let baseURL: URL
    let title: String
}

/// 一个来源当前可用的 Host 状态：候选线路与实际绑定的 Base URL。
struct SourceHostSelectionSnapshot: Hashable, Sendable {
    let candidates: [SourceHostCandidate]
    let activeBaseURL: URL

    /// 创建一份已经由具体来源校验完成的 Host 快照。
    init(candidates: [SourceHostCandidate], activeBaseURL: URL) {
        self.candidates = candidates
        self.activeBaseURL = activeBaseURL
    }
}

/// 描述 Host 选择或应用失败的原因。
enum SourceHostSelectionError: Error, Hashable, Sendable {
    /// 待保存的地址不属于该来源当前允许选择的候选列表。
    case baseURLUnavailable

    /// 来源当前无法取得可用的 Host 候选列表或快照。
    case candidatesUnavailable
}
