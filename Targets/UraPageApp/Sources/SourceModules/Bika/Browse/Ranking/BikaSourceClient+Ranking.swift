import Alamofire

extension BikaSourceClient {
    /// 请求指定周期的完整漫画榜。
    ///
    /// 单次请求的完整榜单，不在来源层去重；单张坏卡片跳过。
    func comicRanking(period: BikaComicRankingPeriod) async throws -> [ComicListItem] {
        let response = try await read { state in
            try await state.session
                .request(
                    "comics/leaderboard",
                    method: .get,
                    parameters: [
                        "tt": period.requestValue,
                        "ct": "VC",
                    ],
                    encoding: URLEncoding(destination: .queryString),
                )
                .bikaDecodedResponse(as: BikaComicRankingResponseDTO.self)
        }

        return SourceItemMapping
            .compactMap(response.comics, category: "Bika.Ranking") { makeBikaComicListItem(from: $0) }
    }

    /// 请求完整骑士榜，保留服务端返回的用户顺序。
    ///
    /// 缺少有效账号 identity 的单个用户不应让完整骑士榜进入失败状态。
    func knightRanking() async throws -> [BikaKnightRankingItem] {
        let response = try await read { state in
            try await state.session
                .request("comics/knight-leaderboard", method: .get)
                .bikaDecodedResponse(as: BikaKnightRankingResponseDTO.self)
        }

        return SourceItemMapping
            .compactMap(response.users, category: "Bika.Ranking") { makeBikaKnightRankingItem(from: $0) }
    }
}
