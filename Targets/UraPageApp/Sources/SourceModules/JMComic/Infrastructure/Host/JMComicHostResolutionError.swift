import Foundation

/// 描述禁漫 API Host 准备过程中可能发生的源内错误。
enum JMComicHostResolutionError: Error {
    /// bootstrap 请求未返回成功的 HTTPS 响应，或响应内容为空或不是 UTF-8 文本。
    case invalidBootstrapResponse

    /// Host 列表密文无法进行 Base64 解码或 AES-ECB 解密。
    case hostDecryptionFailed

    /// 解密结果不是预期 JSON。
    case invalidHostPayload

    /// 解密后的 Host 列表没有任何可供选择的服务器。
    case emptyServerList
}
