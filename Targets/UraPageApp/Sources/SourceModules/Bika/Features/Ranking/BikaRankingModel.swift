import Observation

/// 哔咔排行榜页面的状态：三个漫画榜周期各自独立加载、各自缓存，骑士榜单独一份列表状态。
///
/// 漫画榜用公共分页执行器承载（整份榜单一次取回，`continuation` 直接 `.end`），
/// 骑士榜的条目不是漫画卡片，因此用公共 `SourceValueLoadModel` 持有首屏状态与重试。
@MainActor
@Observable
final class BikaRankingModel {
    let daily: ComicPagingModel<BikaComicRankingPeriod, Int>
    let weekly: ComicPagingModel<BikaComicRankingPeriod, Int>
    let monthly: ComicPagingModel<BikaComicRankingPeriod, Int>
    let knights: SourceValueLoadModel<[BikaKnightRankingItem]>

    init(services: BikaServices) {
        daily = Self.makeComicRankingModel(services: services, period: .daily)
        weekly = Self.makeComicRankingModel(services: services, period: .weekly)
        monthly = Self.makeComicRankingModel(services: services, period: .monthly)
        knights = SourceValueLoadModel(logCategory: "Bika.Ranking") {
            try await services.knightRanking()
        }
    }

    /// 指定周期的漫画榜状态。
    func comicRankingModel(
        for period: BikaComicRankingPeriod,
    ) -> ComicPagingModel<BikaComicRankingPeriod, Int> {
        switch period {
        case .daily:
            daily
        case .weekly:
            weekly
        case .monthly:
            monthly
        }
    }

    /// 只在当前分页尚未请求时开始加载，切回已有结果的页面不会重复请求。
    func loadIfNeeded(for page: BikaRankingPage) {
        switch page {
        case let .comic(period):
            comicRankingModel(for: period).loadIfNeeded(query: period)
        case .knights:
            knights.loadIfNeeded()
        }
    }

    /// 创建一个周期的漫画榜执行器：整份榜单一次取回，没有下一页。
    private static func makeComicRankingModel(
        services: BikaServices,
        period: BikaComicRankingPeriod,
    ) -> ComicPagingModel<BikaComicRankingPeriod, Int> {
        ComicPagingModel(loadPage: { query, _ in
            try await ComicPageSlice(
                items: services.comicRanking(period: query),
                continuation: .end,
            )
        })
    }
}
