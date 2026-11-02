import Foundation

/// 导出一个已下载作品所需的只读计划：展示名称、封面文件与各章节的页面文件位置。
///
/// 由 `DownloadManager.makeExportPlan(for:)` 在已下载完成的作品上一次性构建：包含封面在内
/// 的所有 URL 都已按资产路径规则做过 containment 校验，导出器只做顺序读取与打包，
/// 不再访问持久化、网络或来源。
struct ComicExportPlan: Sendable {
    /// 作品展示名称；用作压缩包名与顶层目录名（导出时按文件系统规则清洗）。
    let title: String

    /// 本地封面文件；下载完成态必有封面，缺失时计划构建阶段即按资产不完整失败。
    let coverFileURL: URL

    /// 按章节顺序排列的章节，每项含该章按页序号排列的页文件。
    let chapters: [ComicExportChapter]

    /// 全部章节的页文件总数；用于进度分母。
    let totalPageCount: Int
}

/// 导出计划中的一个章节：标题与按序排列的页文件。
struct ComicExportChapter: Sendable {
    let title: String
    let pages: [URL]
}

/// 导出失败原因；页面把 `message` 直接展示给用户，不区分内部细节。
enum ComicExportError: Error, Equatable, Sendable {
    /// 作品不是下载完成状态（进行中、暂停、失败或没有记录）。
    case notCompleted

    /// 本地资产不完整：章节记录、清单或页文件与完成状态不一致。
    case incompleteAssets

    /// 无法在临时目录创建压缩包文件。
    case cannotWriteArchive

    /// 导出过程中存储空间不足。
    case insufficientSpace

    var message: String {
        switch self {
        case .notCompleted:
            "该作品尚未下载完成，无法导出"
        case .incompleteAssets:
            "本地下载数据不完整，无法导出"
        case .cannotWriteArchive:
            "无法创建导出文件，请稍后重试"
        case .insufficientSpace:
            "存储空间不足，无法完成导出"
        }
    }
}
