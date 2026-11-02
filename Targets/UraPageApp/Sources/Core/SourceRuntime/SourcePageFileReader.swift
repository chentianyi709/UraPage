import Foundation

/// 阅读页文件的公共读取：映射读取、空文件校验与取消检查只实现一次。
///
/// 所有入口都在 `@concurrent` 上运行，避免阻塞章节句柄或来源 Client 状态 actor；
/// 需要解扰或解码的来源在 `@concurrent` 规则内叠加自己的处理。
enum SourcePageFileReader {
    /// 原样返回的页面载荷；不需要解密或解扰的来源直接使用。
    @concurrent
    static func encodedPayload(from fileURL: URL) async throws -> SourcePagePayload {
        try .encoded(read(from: fileURL))
    }

    /// 读取页面文件字节；供需要解扰或解码的 `@concurrent` 规则复用。
    @concurrent
    static func data(from fileURL: URL) async throws -> Data {
        try read(from: fileURL)
    }

    /// 映射读取与公共校验；只允许从本类型的 `@concurrent` 入口调用。
    private static func read(from fileURL: URL) throws -> Data {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard !data.isEmpty else {
            throw ComicSourceError.invalidResponse
        }

        try Task.checkCancellation()
        return data
    }
}
