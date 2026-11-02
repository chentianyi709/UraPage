import Foundation

/// 描述绅士 Host 准备过程中可能发生的源内错误。
enum ShenshiHostResolutionError: Error {
    /// 所有发布页均请求失败、返回重定向，或响应为空、不是 UTF-8 HTML。
    case invalidBootstrapResponse

    /// 发布页 HTML 无法解析为可查询的文档。
    case invalidBootstrapHTML

    /// 发布页没有包含任何带“最新地址”标记且能转换成 URL 的地址。
    case emptyHostList
}
