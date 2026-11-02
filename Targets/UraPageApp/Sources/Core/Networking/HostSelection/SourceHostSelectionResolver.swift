import Foundation

/// 集中处理多个来源真实共用的无状态 Host 候选选择规则。
enum SourceHostSelectionResolver {
    /// 使用完整绝对字符串在候选列表中查找线路。
    static func candidate(
        matching baseURL: String,
        in candidates: [SourceHostCandidate],
    ) -> SourceHostCandidate? {
        candidates.first { $0.baseURL.absoluteString == baseURL }
    }

    /// 用候选列表和已选偏好构建快照。
    ///
    /// 候选按完整绝对地址去重（保留首次出现的线路），同一个地址只会对应菜单里的一项；
    /// 已选地址仍存在于候选中时继续使用，否则固定到候选列表第一个地址；
    /// 没有候选时抛出 `candidatesUnavailable`。
    static func snapshot(
        candidates: [SourceHostCandidate],
        preferredBaseURL: URL?,
    ) throws -> SourceHostSelectionSnapshot {
        let uniqueCandidates = deduplicated(candidates)
        guard let firstCandidate = uniqueCandidates.first else {
            throw SourceHostSelectionError.candidatesUnavailable
        }

        let activeBaseURL = preferredBaseURL
            .flatMap { candidate(matching: $0.absoluteString, in: uniqueCandidates)?.baseURL }
            ?? firstCandidate.baseURL

        return SourceHostSelectionSnapshot(candidates: uniqueCandidates, activeBaseURL: activeBaseURL)
    }

    /// 去掉地址重复的候选；同一线路地址以第一次出现的展示名与顺序为准。
    private static func deduplicated(_ candidates: [SourceHostCandidate]) -> [SourceHostCandidate] {
        var seenBaseURLs: Set<String> = []
        return candidates.filter { seenBaseURLs.insert($0.baseURL.absoluteString).inserted }
    }
}
