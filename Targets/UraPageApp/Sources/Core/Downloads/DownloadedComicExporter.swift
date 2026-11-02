import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 把已下载作品的本地资产导出为一个 ZIP：顶层目录是作品名，章节目录是「三位序号 章节名」，
/// 页文件是 001、002…，封面固定在作品目录下、名为 `cover`。
///
/// 只做「顺序读取本地资产 → 组织目录 → 打包」，不转码：页文件与封面保持来源原始字节，
/// 仅按内容识别格式补上正确扩展名（图片本身已是压缩格式，二次编码只会损失画质）。
/// 导出在并发执行器上运行、按百分比回调进度并响应取消：取消或失败时删除整个临时目录，
/// 成功时把 ZIP 留在临时目录，由调用方分享并按生命周期清理。
enum DownloadedComicExporter {
    /// 导出为 ZIP 并返回压缩包 URL；`onProgress` 从后台执行器回调整数百分比（0...100）。
    ///
    /// `directory` 由调用方提前登记并负责在失败、取消或页面释放时清理，导出器只创建和使用它。
    @concurrent
    static func export(
        _ plan: ComicExportPlan,
        in directory: URL,
        onProgress: @Sendable (_ percent: Int) -> Void,
    ) async throws -> URL {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let comicName = ComicExportNaming.sanitizedComponent(plan.title, fallback: "漫画")
            let archiveURL = directory.appending(path: "\(comicName).zip", directoryHint: .notDirectory)
            let writer = try ZipArchiveWriter(destinationURL: archiveURL)
            let modifiedAt = Date()

            try Task.checkCancellation()
            let coverURL = plan.coverFileURL
            let coverData = try readAsset(at: coverURL)
            guard let coverExtension = imageFileExtension(
                for: coverData,
                name: coverURL.lastPathComponent,
            ) else {
                throw ComicExportError.incompleteAssets
            }

            try writer.addData(
                coverData,
                path: "\(comicName)/\(ComicExportNaming.coverFileName(extension: coverExtension))",
                modificationDate: modifiedAt,
            )

            var processedPageCount = 0
            var lastReportedPercent = -1
            for (chapterIndex, chapter) in plan.chapters.enumerated() {
                try Task.checkCancellation()

                let chapterName = ComicExportNaming.chapterDirectoryName(
                    position: chapterIndex + 1,
                    title: chapter.title,
                )
                for (pageIndex, pageURL) in chapter.pages.enumerated() {
                    try Task.checkCancellation()

                    let data = try readAsset(at: pageURL)
                    guard let fileExtension = imageFileExtension(
                        for: data,
                        name: pageURL.lastPathComponent,
                    ) else {
                        throw ComicExportError.incompleteAssets
                    }

                    let pageName = ComicExportNaming.pageFileName(
                        position: pageIndex + 1,
                        extension: fileExtension,
                    )
                    try writer.addData(
                        data,
                        path: "\(comicName)/\(chapterName)/\(pageName)",
                        modificationDate: modifiedAt,
                    )

                    // 只在整数百分比变化时上报：封面进度不必为每一页重建一次网格。
                    processedPageCount += 1
                    let percent = plan.totalPageCount > 0
                        ? processedPageCount * 100 / plan.totalPageCount
                        : 0
                    if percent != lastReportedPercent {
                        lastReportedPercent = percent
                        onProgress(percent)
                    }
                }
            }

            try writer.finish()
            return archiveURL
        } catch {
            // 取消与失败都不保留半成品：临时目录整体删除，不留下不完整压缩包。
            try? FileManager.default.removeItem(at: directory)
            throw isOutOfSpace(error) ? ComicExportError.insufficientSpace : error
        }
    }

    /// `Data.write` 与 `FileHandle` 可能分别以 Cocoa、POSIX 错误报告磁盘写满，统一映射。
    private static func isOutOfSpace(_ error: any Error) -> Bool {
        if let cocoaError = error as? CocoaError, cocoaError.code == .fileWriteOutOfSpace {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSPOSIXErrorDomain
            && nsError.code == Int(POSIXErrorCode.ENOSPC.rawValue)
    }

    /// 按文件内容识别图片格式并返回扩展名；无法识别时返回 `nil`，不猜测格式。
    ///
    /// 与写 ZIP 复用同一次读取；`name` 只用于日志定位。
    private static func imageFileExtension(for data: Data, name: String) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source),
              let fileExtension = UTType(typeIdentifier as String)?.preferredFilenameExtension
        else {
            AppLogger.warning(
                "导出无法识别图片格式，name=\(name)，bytes=\(data.count)",
                category: "App.Download",
            )
            return nil
        }

        // JPEG 统一用更常见的 `jpg`，与用户对导出的图片文件预期一致。
        return fileExtension == "jpeg" ? "jpg" : fileExtension
    }

    /// 读取一份本地资产；记录仍在但文件已丢失／不可读时按「本地资产不完整」反馈，
    /// 不把它落到笼统的读写失败上。
    private static func readAsset(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            AppLogger.warning(
                "导出读取本地资产失败，name=\(url.lastPathComponent)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            throw ComicExportError.incompleteAssets
        }
    }
}
