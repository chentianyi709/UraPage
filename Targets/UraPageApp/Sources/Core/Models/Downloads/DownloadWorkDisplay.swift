/// 下载调度构建进度快照所需的作品展示值。
struct DownloadWorkDisplay: Sendable {
    let title: String
    let authors: [String]
    let cover: ComicImageSource
    let coverState: DownloadState
}
