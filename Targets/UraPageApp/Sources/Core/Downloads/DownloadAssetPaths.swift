import CryptoKit
import Foundation
import Synchronization

/// 下载资产的路径规则（纯计算 + 目录创建）。
///
/// 目录名一律用来源身份的摘要，不含来源原文；下载页和封面先写入独占临时文件，
/// 处理后写入正式章节目录，再由资产库按 manifest 索引。
enum DownloadAssetPaths {
    private static let baseURL = Mutex<URL?>(nil)

    /// 下载资产根目录（Application Support 下）；首次调用时创建。
    static func baseDirectory() throws -> URL {
        if let cached = baseURL.withLock({ $0 }) {
            return cached
        }

        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true,
        )
        let directory = assetDirectory(in: support)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        baseURL.withLock { $0 = directory }
        return directory
    }

    /// 已存在的下载资产根目录；从未创建过时返回 `nil`。
    ///
    /// 供只读统计使用：资产目录只在首次下载时创建，空安装下统计不应顺手建目录。
    static func baseDirectoryIfExists() throws -> URL? {
        if let cached = baseURL.withLock({ $0 }) {
            return cached
        }

        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false,
        )
        let directory = assetDirectory(in: support)
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }

        return directory
    }

    private static func assetDirectory(in support: URL) -> URL {
        support.appending(
            path: AppConfiguration.Downloads.assetsDirectory,
            directoryHint: .isDirectory,
        )
    }

    /// 作品正式资产目录：`<来源>/<作品摘要>/`。
    static func comicDirectory(for comic: ComicIdentity) throws -> URL {
        try comicDirectory(sourceID: comic.sourceID.rawValue, comicID: comic.comicID)
    }

    /// 作品封面文件 URL；封面引用的 `ownerID` 就是作品 ID。
    static func coverURL(for reference: ComicImageReference) throws -> URL {
        let directory = try comicDirectory(sourceID: reference.sourceID.rawValue, comicID: reference.ownerID)
        let url = directory
            .appending(path: coverRelativePath(for: reference), directoryHint: .notDirectory)
            .resolvingSymlinksInPath()
        guard isContained(url, in: directory) else {
            throw DownloadAssetError.unsafeRelativePath
        }

        return url
    }

    /// 作品目录（原始标识版本）：`<来源>/<作品摘要>/`；来源不可识别时仍可定位旧资产的目录。
    static func comicDirectory(sourceID: String, comicID: String) throws -> URL {
        let base = try baseDirectory().resolvingSymlinksInPath().standardizedFileURL
        let directory = base
            .appending(path: sourceID, directoryHint: .isDirectory)
            .appending(path: comicDigest(sourceID: sourceID, comicID: comicID), directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard isContained(directory, in: base), directory != base else {
            throw DownloadAssetError.unsafeRelativePath
        }

        return directory
    }

    /// 下载封面文件按远程引用的稳定身份生成文件名，避免旧任务覆盖新任务的字节。
    ///
    /// 身份取来源提供的 `assetIdentity`（path，或需要 query 时的 `path?query`）；
    /// 没有时只取 locator 的 path。Host、scheme、fragment 和 locator 的 query 默认不参与，
    /// 因此切换文件服务或服务端在地址上附加签名、版本号等请求参数不会产生新文件名。
    /// 需要按 query 区分封面内容的来源在 `assetIdentity` 中显式提供稳定身份。
    static func coverRelativePath(for reference: ComicImageReference) -> String {
        let variant = reference.variant.map { "some:\($0)" } ?? "none"
        let identity = reference.assetIdentity
            ?? SourceImageIdentity.components(ofLocator: reference.locator).path
        let referenceDigest = digest([
            "cover",
            reference.sourceID.rawValue,
            reference.ownerID,
            identity,
            reference.purpose.rawValue,
            variant,
        ])
        return "cover-\(referenceDigest).bin"
    }

    /// 章节正式资产目录：`<来源>/<作品摘要>/<章节摘要>/`。
    static func chapterDirectory(for chapter: ChapterIdentity) throws -> URL {
        let comic = try comicDirectory(for: chapter.comic)
        let directory = comic
            .appending(path: chapterDigest(chapter), directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard isContained(directory, in: comic), directory != comic else {
            throw DownloadAssetError.unsafeRelativePath
        }

        return directory
    }

    /// 章节清单文件 URL。
    static func manifestURL(for chapter: ChapterIdentity) throws -> URL {
        let directory = try chapterDirectory(for: chapter)
        let url = directory.appending(path: "manifest.json", directoryHint: .notDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard isContained(url, in: directory.resolvingSymlinksInPath().standardizedFileURL) else {
            throw DownloadAssetError.unsafeRelativePath
        }

        return url
    }

    /// 页文件名：`<序号>-<pageID 摘要>.bin`。
    static func pageFileName(index: Int, pageID: String) -> String {
        String(format: "%05d-%@.bin", index, digest(["page", pageID]))
    }

    private static func comicDigest(sourceID: String, comicID: String) -> String {
        digest(["comic", sourceID, comicID])
    }

    private static func chapterDigest(_ chapter: ChapterIdentity) -> String {
        digest(["chapter", chapter.comic.sourceID.rawValue, chapter.comic.comicID, chapter.chapterID])
    }

    /// 组件经无歧义编码后取 SHA-256 十六进制。
    private static func digest(_ components: [String]) -> String {
        SourceDigest.hex(SHA256.hash(data: IdentityKeyEncoder.v1(components)))
    }

    /// 目标路径是否落在允许目录内（含目录本身）；调用方负责先解析符号链接。
    static func isContained(_ url: URL, in directory: URL) -> Bool {
        let base = directory.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        return target == base || target.hasPrefix(base + "/")
    }
}
