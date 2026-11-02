/// 章节与封面下载的持久化状态。
///
/// 阶段（获取章节信息、分页、页图片）不再是状态，而是运行时单位进度；
/// 作品级状态由章节与封面状态聚合，不单独持久化。
nonisolated enum DownloadState: String, CaseIterable, Codable, Hashable, Sendable {
    /// 已入队、等待调度。
    case queued

    /// 正在处理当前章节或封面；具体进度见运行时的单位进度。
    case downloading

    /// 用户暂停。
    case paused

    /// 完成（含作品完成要求的封面）。
    case completed

    /// 失败（含“部分页已下、仍缺页”，可重试补齐）。
    case failed

    /// 排队或正在处理的任务都可以暂停。
    var canPause: Bool {
        switch self {
        case .queued, .downloading:
            true
        case .paused, .completed, .failed:
            false
        }
    }
}
