import Alamofire

/// 一个作品 ID 的卡片补齐结果；单项失败不抹掉同批可用卡片。
private enum BikaRecommendationItemOutcome: Sendable {
    case item(index: Int, comic: ComicListItem)
    case failure(ComicSourceError)
    case cancelled
}

extension BikaSourceClient {
    /// 官方相关推荐使用业务 Session，沿用当前账号凭证与认证失效处理。
    func officialRecommendations(comicID: String) async throws -> [ComicListItem] {
        let response = try await read { state in
            try await state.session
                .request("comics/\(comicID)/recommendation", method: .get)
                .bikaDecodedResponse(as: BikaComicRecommendationResponseDTO.self)
        }
        return response.comics.compactMap(makeBikaComicListItem(from:))
    }

    /// 把独立服务返回的有序 ID 补齐为卡片；每批最多并行三个详情请求。
    func recommendationComicItems(for comicIDs: [String]) async throws -> [ComicListItem] {
        var indexedItems: [(index: Int, comic: ComicListItem)] = []
        var firstFailure: ComicSourceError?
        let concurrency = BikaConfiguration.Recommendation.maximumHydrationConcurrency

        for chunkStart in stride(from: comicIDs.startIndex, to: comicIDs.endIndex, by: concurrency) {
            try Task.checkCancellation()
            let chunkEnd = min(chunkStart + concurrency, comicIDs.endIndex)
            let outcomes = await withTaskGroup(of: BikaRecommendationItemOutcome.self) { group in
                for index in chunkStart ..< chunkEnd {
                    group.addTask { [self] in
                        await recommendationItem(comicID: comicIDs[index], index: index)
                    }
                }

                var outcomes: [BikaRecommendationItemOutcome] = []
                for await outcome in group {
                    outcomes.append(outcome)
                }
                return outcomes
            }

            for outcome in outcomes {
                switch outcome {
                case let .item(index, comic):
                    indexedItems.append((index, comic))

                case let .failure(error):
                    if case .authenticationRequired = error {
                        throw error
                    }
                    firstFailure = firstFailure ?? error

                case .cancelled:
                    throw CancellationError()
                }
            }
        }

        try Task.checkCancellation()
        if indexedItems.isEmpty, !comicIDs.isEmpty, let firstFailure {
            throw firstFailure
        }
        return indexedItems.sorted { $0.index < $1.index }.map(\.comic)
    }

    /// 详情响应来自服务端，但必须与请求的作品 ID 对应。
    private func recommendationItem(comicID: String, index: Int) async -> BikaRecommendationItemOutcome {
        do {
            let response = try await read { state in
                try await state.session
                    .request("comics/\(comicID)", method: .get)
                    .bikaDecodedResponse(as: BikaComicDetailResponseDTO.self)
            }
            guard response.comic.id == comicID,
                  let comic = makeBikaComicListItem(from: response.comic)
            else {
                return .failure(.invalidResponse)
            }

            return .item(index: index, comic: comic)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(SourceErrorMapper.map(error) as? ComicSourceError ?? .invalidResponse)
        }
    }
}
