import Foundation

/// 禁漫 Host 发现：下载固定 bootstrap、AES 解密并解析候选列表。
///
/// 只负责“发现候选”，不缓存、不选择、不保存偏好——这些由 `SourceHostProvider` 完成。
/// 远程全部失败时使用代码内置兜底密文。
struct JMComicHostDiscovery: Sendable {
    /// 按配置顺序尝试 bootstrap；任意一个返回可解析列表即停止；全部失败则用内置兜底。
    func discoverCandidates() async throws -> [SourceHostCandidate] {
        for bootstrapURL in JMComicConfiguration.Host.bootstrapURLs {
            try Task.checkCancellation()

            do {
                let encryptedPayload = try await fetchEncryptedPayload(from: bootstrapURL)
                let payload = try Self.decodePayload(from: encryptedPayload)
                let candidates = try Self.candidates(in: payload)
                AppLogger.debug("Host 候选获取成功，count=\(candidates.count)", category: "JM.Host")
                return candidates
            } catch {
                // 跨 Alamofire 边界的取消可能不是 CancellationError，必须用公共判定。
                if SourceNetworkErrorMapper.isCancellation(error) {
                    throw CancellationError()
                }
                AppLogger.warning("Host 候选获取失败，继续下一个 bootstrap", category: "JM.Host")
                continue
            }
        }

        AppLogger.warning("远程 Host 候选全部失败，改用内置候选", category: "JM.Host")
        let fallbackPayload = try Self.decodePayload(from: JMComicConfiguration.Host.fallbackHostCipher)
        return try Self.candidates(in: fallbackPayload)
    }

    /// 下载并校验一份加密 Host 列表文本。
    private func fetchEncryptedPayload(from url: URL) async throws -> String {
        let data: Data
        do {
            data = try await SourceBootstrapLoader.shared.data(from: url)
        } catch {
            // 取消必须原样传播，不能被包装成 bootstrap 失败。
            if SourceNetworkErrorMapper.isCancellation(error) {
                throw CancellationError()
            }
            throw JMComicHostResolutionError.invalidBootstrapResponse
        }

        guard let payload = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !payload.isEmpty
        else {
            throw JMComicHostResolutionError.invalidBootstrapResponse
        }

        return payload
    }

    /// 解密并解析 Host JSON，不向源外暴露响应字段。
    private static func decodePayload(from encryptedPayload: String) throws -> JMComicHostPayload {
        let data: Data
        do {
            data = try JMComicAESCipher.decrypt(encryptedPayload, key: JMComicConfiguration.Host.cipherKey)
        } catch {
            throw JMComicHostResolutionError.hostDecryptionFailed
        }

        do {
            return try JSONDecoder().decode(JMComicHostPayload.self, from: data)
        } catch {
            throw JMComicHostResolutionError.invalidHostPayload
        }
    }

    /// 将服务端地址与线路名转换为展示候选；完整 URL 原样使用，无 scheme 时只补 HTTPS。
    ///
    /// 候选优先取 `jm3_Server`（每项 `[域名, 线路名]`，含网页显示的全部线路）；
    /// 它缺失、为空或全部无效时回退 `Server`（只有域名，按顺序生成「线路N」）。
    private static func candidates(in payload: JMComicHostPayload) throws -> [SourceHostCandidate] {
        let namedCandidates = makeCandidates(from: payload.jm3Server ?? [])
        if !namedCandidates.isEmpty {
            return namedCandidates
        }

        let fallbackCandidates = makeCandidates(from: payload.servers.map { [$0] })
        guard !fallbackCandidates.isEmpty else {
            throw JMComicHostResolutionError.emptyServerList
        }

        return fallbackCandidates
    }

    /// 把「域名＋可选线路名」条目转换为候选，跳过无法解析地址的条目。
    private static func makeCandidates(from entries: [[String]]) -> [SourceHostCandidate] {
        var candidates: [SourceHostCandidate] = []
        candidates.reserveCapacity(entries.count)

        for entry in entries {
            guard let value = entry.first, let baseURL = makeBaseURL(value) else {
                continue
            }

            let name = entry.count > 1 ? entry[1].trimmingCharacters(in: .whitespaces) : ""
            let title = name.isEmpty ? "线路\(candidates.count + 1)" : name.convertedToSimplifiedChinese()
            candidates.append(SourceHostCandidate(baseURL: baseURL, title: title))
        }

        return candidates
    }

    /// 地址缺失 scheme 时补 HTTPS。
    private static func makeBaseURL(_ value: String) -> URL? {
        URL(string: value.contains("://") ? value : "https://\(value)")
    }
}
