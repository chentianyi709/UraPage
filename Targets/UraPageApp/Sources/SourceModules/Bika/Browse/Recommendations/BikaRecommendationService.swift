import Foundation

/// 哔咔推荐业务：并发读取官方与独立推荐，并统一合并、失败和跳转记录规则。
struct BikaRecommendationService: Sendable {
    private let client: BikaSourceClient
    private let personalizedClient = BikaPersonalizedRecommendationClient()

    init(client: BikaSourceClient) {
        self.client = client
    }

    /// 单边失败时保留另一边的真实结果；哔咔接口认证失败仍要求重新登录。
    func recommendations(for identity: ComicIdentity) async throws -> [ComicListItem] {
        try await SourceServiceOperation.run(failureMessage: "漫画推荐加载失败", category: "Bika.Recommendations") {
            async let officialOutcome = Self.recommendationOutcome {
                try await client.officialRecommendations(comicID: identity.comicID)
            }
            async let personalizedOutcome = personalizedRecommendationOutcome(for: identity.comicID)

            let officialResult = await officialOutcome
            let personalizedResult = await personalizedOutcome
            try Task.checkCancellation()

            var items: [ComicListItem] = []
            var hasSuccess = false
            var firstFailure: ComicSourceError?
            for outcome in [officialResult, personalizedResult] {
                switch outcome {
                case let .success(recommendations):
                    hasSuccess = true
                    items.append(contentsOf: recommendations)

                case let .failure(error):
                    firstFailure = firstFailure ?? error

                case .sourceAuthenticationRequired:
                    throw ComicSourceError.authenticationRequired

                case .cancelled: throw CancellationError()
                }
            }

            if let firstFailure {
                guard hasSuccess else { throw firstFailure }

                AppLogger.warning("一个推荐提供方不可用，继续使用其余成功结果", category: "Bika.Recommendations")
            }

            var seen = Set<ComicIdentity>()
            return items
                .filter { $0.identity != identity && seen.insert($0.identity).inserted }
        }
    }

    /// 记录作品间跳转；失败由详情页决定是否影响展示。
    func recordTransition(to identity: ComicIdentity) async throws {
        try await SourceServiceOperation.run(
            failureMessage: "个性化推荐跳转记录失败",
            category: "Bika.Recommendations",
        ) {
            try await personalizedClient.recordTransition(to: identity.comicID)
        }
    }

    /// 独立服务只给 ID；随后补齐卡片的请求才使用哔咔账号，两段认证错误不能混为一谈。
    private func personalizedRecommendationOutcome(for comicID: String) async -> BikaRecommendationOutcome {
        let ids: [String]
        do {
            ids = try await personalizedClient.recommendationComicIDs(for: comicID)
                .filter { $0 != comicID }
        } catch {
            return Self.recommendationFailure(error, usesBikaAccount: false)
        }

        do {
            return try await .success(client.recommendationComicItems(for: ids))
        } catch {
            return Self.recommendationFailure(error, usesBikaAccount: true)
        }
    }

    /// 在并发边界内把提供方失败收敛为可发送的公开错误，并保留取消语义。
    private static func recommendationOutcome(
        operation: @Sendable () async throws -> [ComicListItem],
    ) async -> BikaRecommendationOutcome {
        do {
            return try await .success(operation())
        } catch {
            return recommendationFailure(error, usesBikaAccount: true)
        }
    }

    private static func recommendationFailure(
        _ error: any Error,
        usesBikaAccount: Bool,
    ) -> BikaRecommendationOutcome {
        let mappedError = SourceErrorMapper.map(error)
        if mappedError is CancellationError {
            return .cancelled
        }

        let sourceError = mappedError as? ComicSourceError ?? .invalidResponse
        if usesBikaAccount, case .authenticationRequired = sourceError {
            return .sourceAuthenticationRequired
        }
        return .failure(sourceError)
    }
}

private enum BikaRecommendationOutcome: Sendable {
    case success([ComicListItem])
    case failure(ComicSourceError)
    case sourceAuthenticationRequired
    case cancelled
}
