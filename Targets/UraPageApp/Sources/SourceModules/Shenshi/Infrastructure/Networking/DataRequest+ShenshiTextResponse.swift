import Alamofire
import Foundation

extension DataRequest {
    /// 校验绅士文本响应、转换 UTF-8，并交给具体 HTML 或脚本解析器。
    ///
    /// 传输层统一校验编码；解析错误由 `transform` 抛出，来源边界再映射为公共错误。
    func shenshiParsedTextResponse<Response: Sendable>(
        transform: @Sendable (String) throws -> Response,
    ) async throws -> Response {
        // HTTP 请求成功后才读取正文，非成功状态交给公共网络错误映射处理。
        let data = try await validate(statusCode: 200 ..< 300)
            .serializingData()
            .value

        return try await ShenshiTextResponseWorker.parse(data, transform: transform)
    }
}

/// 正文编码校验与整页解析都是重活；放到并发执行器，不占用来源 Client 状态 actor。
private enum ShenshiTextResponseWorker {
    @concurrent
    static func parse<Response: Sendable>(
        _ data: Data,
        transform: @Sendable (String) throws -> Response,
    ) async throws -> Response {
        // HTML 与 Reader 数据脚本当前都使用 UTF-8；传输层在这里统一校验编码。
        guard let text = String(data: data, encoding: .utf8) else {
            AppLogger.error("文本响应不是 UTF-8，bytes=\(data.count)", category: "Shenshi.Network")
            throw ShenshiAPIError.invalidResponse
        }

        return try transform(text)
    }
}
