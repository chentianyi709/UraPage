import Foundation

/// 绅士 Host 发现：按配置顺序解析发布页，返回第一份成功解析的候选地址。
///
/// 绅士没有代码内置兜底，全部发布页失败即抛错。
/// 只负责发现，不缓存、不选择、不保存偏好——这些由 `SourceHostProvider` 完成。
struct ShenshiHostDiscovery: Sendable {
    /// 按配置顺序尝试发布页，任意一个成功即停止。
    func discoverCandidates() async throws -> [SourceHostCandidate] {
        for bootstrapURL in ShenshiConfiguration.Host.bootstrapURLs {
            try Task.checkCancellation()

            do {
                let html = try await fetchBootstrapHTML(from: bootstrapURL)
                let candidates = try Self.candidates(from: ShenshiHostHTMLParser.baseURLs(from: html))
                AppLogger.debug("Host 候选解析成功，count=\(candidates.count)", category: "Shenshi.Host")
                return candidates
            } catch {
                // 跨边界取消可能是 Alamofire 的取消错误，必须用公共判定。
                if SourceNetworkErrorMapper.isCancellation(error) {
                    throw CancellationError()
                }
                AppLogger.warning("发布页解析失败，继续下一个", category: "Shenshi.Host")
            }
        }

        throw ShenshiHostResolutionError.invalidBootstrapResponse
    }

    /// 发布页只提供地址、没有线路名：按顺序生成「线路N」，与其它来源的菜单形态一致。
    private static func candidates(from baseURLs: [URL]) -> [SourceHostCandidate] {
        baseURLs.enumerated().map { index, baseURL in
            SourceHostCandidate(baseURL: baseURL, title: "线路\(index + 1)")
        }
    }

    /// 获取并校验一个固定发布页的 HTML。
    private func fetchBootstrapHTML(from bootstrapURL: URL) async throws -> String {
        let data: Data
        do {
            data = try await SourceBootstrapLoader.shared.data(from: bootstrapURL)
        } catch {
            if SourceNetworkErrorMapper.isCancellation(error) {
                throw CancellationError()
            }
            throw ShenshiHostResolutionError.invalidBootstrapResponse
        }

        guard let html = String(data: data, encoding: .utf8),
              !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ShenshiHostResolutionError.invalidBootstrapResponse
        }

        return html
    }
}
