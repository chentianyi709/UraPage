import Foundation

/// 哔咔来源模块的唯一公开入口，共享同一个稳定 Source Client。
///
/// 已暴露浏览、详情、点赞、推荐、图片、章节、Host 与账号（登录/退出/资料）能力。
/// TODO: 评论写操作属于后续层。
struct BikaServices: ComicSourceRuntime, SourceHostSettingsProviding, Sendable {
    let sourceID = ComicSourceID.bika

    /// 本源唯一账号 owner：登录/退出、展示资料，并提供门禁读取的访问事实。
    let account: BikaAccount

    private let chapterContent: BikaChapterContentService
    private let client: BikaSourceClient
    private let recommendationService: BikaRecommendationService

    /// 哔咔只有固定候选 Host，由公共 Provider 管理进程内选择。
    ///
    /// `@MainActor`：账号 owner 是 MainActor 隔离的，组合根只在 MainActor 装配一次。
    @MainActor
    init() {
        let hostProvider = SourceHostProvider(sourceID: .bika) {
            BikaHostDiscovery.discoverCandidates()
        }
        let access = BikaAccountAccessStore()
        // 认证失效（401）由 Client 判定并通知账号 owner 清凭证、发布未登录；Client 不直接写 Keychain。
        let client = BikaSourceClient(
            hostProvider: hostProvider,
            access: access,
        )
        self.client = client
        recommendationService = BikaRecommendationService(client: client)
        account = BikaAccount(client: client, access: access)
        chapterContent = BikaChapterContentService(client: client)
    }

    func chapterContentService() -> any SourceChapterContentService {
        chapterContent
    }

    /// 转发哔咔 Client 的 Host 切换成功事件；下载据此重启本源当前线路上的在途章节。
    func hostChangeStream() async -> AsyncStream<SourceHostChange> {
        await client.hostChangeStream()
    }

    /// 登录哔咔账号；成功后 Token 与资料由账号 owner 落盘并发布已登录。
    func login(email: String, password: String) async throws {
        try await SourceServiceOperation.run(failureMessage: "账号登录失败", category: "Bika.Account") {
            try await account.login(account: email, password: password)
        }
    }

    /// 退出哔咔账号：清除 Token 与展示资料；返回是否成功（失败提示由页面给出）。
    @discardableResult
    func logout() async -> Bool {
        await account.logout()
    }

    /// 页面组合边界工厂：每次返回新的页面级图片会话，画质快照随页面固定。
    func makeBrowsingImages() -> any ComicImageService {
        SourceBrowsingImageService(
            source: BikaBrowsingImageSource(sourcePreferences: client.sourcePreferences),
        )
    }

    /// 获取服务端当次生成的随机漫画。
    func randomComics() async throws -> [ComicListItem] {
        try await SourceServiceOperation.run(failureMessage: "随机漫画加载失败", category: "Bika.Home") {
            try await client.randomComics()
        }
    }

    /// 获取一页“新到旧”的最近更新漫画。
    func recentlyUpdatedComics(page: Int) async throws -> BikaComicPage {
        try await SourceServiceOperation.run(
            failureMessage: "最近更新加载失败，page=\(page)",
            category: "Bika.Latest",
        ) {
            try await client.recentlyUpdatedComics(page: page)
        }
    }

    /// 获取哔咔当前可展示的有序分类。
    func categories() async throws -> [BikaComicCategory] {
        try await SourceServiceOperation.run(failureMessage: "分类加载失败", category: "Bika.Categories") {
            try await client.categories()
        }
    }

    /// 获取搜索页的热门搜索推荐词。
    func searchRecommendations() async throws -> [String] {
        try await SourceServiceOperation.run(
            failureMessage: "热门搜索加载失败",
            category: "Bika.Search",
        ) {
            try await client.searchRecommendations()
        }
    }

    /// 按分类/标签/贡献者筛选一页漫画；`filter` 为 `nil` 时不带筛选参数（服务端默认列表）。
    func filteredComics(
        filter: BikaComicListFilter?,
        sort: BikaComicSort,
        page: Int,
    ) async throws -> BikaComicPage {
        try await SourceServiceOperation.run(
            failureMessage: "筛选结果加载失败，page=\(page)",
            category: "Bika.Browse",
        ) {
            try await client.filteredComics(filter: filter, sort: sort, page: page)
        }
    }

    /// 使用关键词、排序和可选多分类搜索一页漫画。
    func searchComics(
        query: String,
        sort: BikaComicSort,
        categories: [BikaComicCategory],
        page: Int,
    ) async throws -> BikaComicPage {
        try await SourceServiceOperation.run(
            failureMessage: "搜索结果加载失败，page=\(page)",
            category: "Bika.Search",
        ) {
            try await client.searchComics(query: query, sort: sort, categories: categories, page: page)
        }
    }

    /// 获取指定周期的完整漫画榜。
    func comicRanking(period: BikaComicRankingPeriod) async throws -> [ComicListItem] {
        try await SourceServiceOperation.run(failureMessage: "漫画榜加载失败", category: "Bika.Ranking") {
            try await client.comicRanking(period: period)
        }
    }

    /// 获取完整骑士榜。
    func knightRanking() async throws -> [BikaKnightRankingItem] {
        try await SourceServiceOperation.run(failureMessage: "骑士榜加载失败", category: "Bika.Ranking") {
            try await client.knightRanking()
        }
    }

    /// 获取哔咔漫画详情与全部章节；身份是否属于本源由跨来源入口校验一次，这里不重复判断。
    func detail(for identity: ComicIdentity) async throws -> BikaComicDetail {
        try await SourceServiceOperation.run(
            failureMessage: "漫画详情加载失败，id=\(identity.comicID)",
            category: "Bika.Detail",
        ) {
            try await client.detail(for: identity)
        }
    }

    /// 切换哔咔作品点赞状态；返回服务端确认的最终状态，不本地取反猜测。
    func toggleComicLike(_ identity: ComicIdentity) async throws -> BikaComicLikeState {
        try await SourceServiceOperation.run(
            failureMessage: "漫画点赞切换失败，id=\(identity.comicID)",
            category: "Bika.Like",
        ) {
            try await client.toggleComicLike(comicID: identity.comicID)
        }
    }

    /// 并发读取官方与个性化推荐；单边失败时继续展示另一边的真实结果。
    func recommendations(for identity: ComicIdentity) async throws -> [ComicListItem] {
        try await recommendationService.recommendations(for: identity)
    }

    /// 记录详情作品间的个性化推荐跳转；失败不影响详情内容展示。
    func recordRecommendationTransition(to identity: ComicIdentity) async throws {
        try await recommendationService.recordTransition(to: identity)
    }

    /// 返回哔咔当前候选地址与实际地址。
    func hostSelectionSnapshot() async throws -> SourceHostSelectionSnapshot {
        try await SourceHostSelectionOperation.run { try await client.hostSelectionSnapshot() }
    }

    /// 固定到一个内置 Host，并让旧 Session 失效。
    func selectHost(baseURL: URL) async throws -> SourceHostSelectionSnapshot {
        try await SourceHostSelectionOperation.run { try await client.selectHost(baseURL: baseURL) }
    }

    /// 返回非阅读页面当前使用的图片清晰度。
    func selectedBrowsingImageQuality() -> BikaImageQuality {
        client.sourcePreferences.browsingImageQuality()
    }

    /// 保存非阅读图片清晰度并立即生效：之后的列表、详情等图片请求与新页面都用新值。
    @discardableResult
    func selectBrowsingImageQuality(_ imageQuality: BikaImageQuality) -> BikaImageQuality {
        client.sourcePreferences.selectBrowsingImageQuality(imageQuality)
        return imageQuality
    }

    /// 返回图片请求是否使用 go2778 CDN 加速。
    func selectedUsesImageCDNAcceleration() -> Bool {
        client.sourcePreferences.usesImageCDNAcceleration()
    }

    /// 保存图片 CDN 加速偏好并立即生效：下一次图片请求即按新线路。
    @discardableResult
    func selectUsesImageCDNAcceleration(_ isEnabled: Bool) -> Bool {
        client.sourcePreferences.selectUsesImageCDNAcceleration(isEnabled)
        return isEnabled
    }
}
