import Alamofire
import Foundation

/// 用来源自己的前台 Session 把章节图片下载到调用方提供的独占临时文件。
enum SourcePageTransfer {
    /// 下载 `request` 到 `fileURL`；任务取消时会同步取消底层网络请求。
    @concurrent
    static func download(_ request: URLRequest, using session: Session, to fileURL: URL) async throws {
        guard fileURL.isFileURL else {
            throw ComicSourceError.invalidIdentity
        }

        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let destination: DownloadRequest.Destination = { _, _ in (fileURL, []) }
        let response = await session
            .download(request, to: destination)
            .validate(statusCode: 200 ..< 300)
            .serializingDownloadedFileURL(automaticallyCancelling: true)
            .response

        switch response.result {
        case .success:
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) > 0 else {
                throw ComicSourceError.invalidResponse
            }

        case let .failure(error):
            if SourceNetworkErrorMapper.isCancellation(error) {
                throw CancellationError()
            }
            throw error
        }
    }
}
