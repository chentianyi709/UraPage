import Foundation

/// 绅士来源模块的唯一公开入口，共享同一个稳定 Source Client。
///
/// 已暴露浏览、详情、图片、章节、Host 与账号（登录/退出/资料）能力。
/// TODO: 评论属于后续层。
struct ShenshiServices: ComicSourceRuntime, SourceHostSettingsProviding, Sendable {
    let sourceID = ComicSourceID.shenshi

    /// 本源唯一账号 owner：登录/退出、展示资料与访问事实。
    let account: ShenshiAccount

    private let chapterContent: ShenshiChapterContentService
    private let client: ShenshiSourceClient

    /// 由本源 Module 创建稳定绅士 Client。
    ///
    /// `@MainActor`：账号 owner 是 MainActor 隔离的，组合根只在 MainActor 装配一次。
    @MainActor
    init() {
        let discovery = ShenshiHostDiscovery()
        let hostProvider = SourceHostProvider(sourceID: .shenshi) {
            try await discovery.discoverCandidates()
        }

        let access = ShenshiAccountAccessStore()
        let client = ShenshiSourceClient(
            hostProvider: hostProvider,
            access: access,
        )
        self.client = client
        account = ShenshiAccount(client: client, access: access)
        chapterContent = ShenshiChapterContentService(client: client)
    }

    func chapterContentService() -> any SourceChapterContentService {
        chapterContent
    }

    /// 转发绅士 Client 的 Host 切换成功事件；下载据此重启本源当前线路上的在途章节。
    func hostChangeStream() async -> AsyncStream<SourceHostChange> {
        await client.hostChangeStream()
    }

    /// 登录绅士账号；成功后由账号 owner 保存 Cookie 与资料并发布已登录。
    func login(username: String, password: String) async throws {
        try await SourceServiceOperation.run(failureMessage: "账号登录失败", category: "Shenshi.Account") {
            try await account.login(account: username, password: password)
        }
    }

    /// 退出绅士账号：清除凭证与展示资料；返回是否成功（失败提示由页面给出）。
    @discardableResult
    func logout() async -> Bool {
        await account.logout()
    }

    /// 页面组合边界工厂：每次返回新的页面级图片会话。
    func makeBrowsingImages() -> any ComicImageService {
        SourceBrowsingImageService(source: ShenshiBrowsingImageSource(client: client))
    }

    /// 获取绅士移动端首页推荐分区。
    func homeSections() async throws -> [ShenshiHomeSection] {
        try await SourceServiceOperation.run(failureMessage: "推荐页加载失败", category: "Shenshi.Recommended") {
            try await client.homeSections()
        }
    }

    /// 获取指定分类和页码的更新漫画。
    func latest(page: Int, categoryID: Int?) async throws -> ShenshiLatestPage {
        try await SourceServiceOperation.run(
            failureMessage: "更新页加载失败，page=\(page)",
            category: "Shenshi.Latest",
        ) {
            try await client.latest(page: page, categoryID: categoryID)
        }
    }

    /// 获取指定周期与分类的收藏排行榜。
    func ranking(
        period: ShenshiRankingPeriod,
        categoryID: Int?,
        page: Int,
    ) async throws -> ShenshiRankingPage {
        try await SourceServiceOperation.run(
            failureMessage: "排行榜加载失败，page=\(page)",
            category: "Shenshi.Ranking",
        ) {
            try await client.ranking(period: period, categoryID: categoryID, page: page)
        }
    }

    /// 使用关键词和页码搜索漫画。
    func searchComics(query: String, page: Int) async throws -> [ComicListItem] {
        try await SourceServiceOperation.run(
            failureMessage: "搜索结果加载失败，page=\(page)",
            category: "Shenshi.Search",
        ) {
            try await client.searchComics(query: query, page: page)
        }
    }

    /// 获取指定发布者的一页投稿及下一页游标。
    func publisherComics(
        publisher: ShenshiComicPublisher,
        cursor: String?,
    ) async throws -> ShenshiPublisherComicPage {
        try await SourceServiceOperation.run(
            failureMessage: "投稿列表加载失败，uid=\(publisher.id)",
            category: "Shenshi.Publisher",
        ) {
            try await client.publisherComics(publisher: publisher, cursor: cursor)
        }
    }

    /// 使用详情页已解析的标签导航 key 与页码获取该标签的漫画列表。
    func tagComics(tag: ShenshiComicTag, page: Int) async throws -> ShenshiTagComicPage {
        try await SourceServiceOperation.run(
            failureMessage: "标签作品加载失败，page=\(page)",
            category: "Shenshi.Tag",
        ) {
            try await client.tagComics(tag: tag, page: page)
        }
    }

    /// 获取绅士漫画详情；身份是否属于本源由跨来源入口校验一次，这里不重复判断。
    func detail(for identity: ComicIdentity) async throws -> ShenshiComicDetail {
        try await SourceServiceOperation.run(
            failureMessage: "漫画详情加载失败，id=\(identity.comicID)",
            category: "Shenshi.Detail",
        ) {
            try await client.detail(comicID: identity.comicID)
        }
    }

    /// 生成当前 Base URL 下的可分享详情地址。
    func detailPageURL(comicID: String) async throws -> URL {
        try await SourceServiceOperation.run(
            failureMessage: "详情地址生成失败，id=\(comicID)",
            category: "Shenshi.Detail",
        ) {
            try await client.detailPageURL(comicID: comicID)
        }
    }

    /// 返回绅士当前候选地址与实际地址。
    func hostSelectionSnapshot() async throws -> SourceHostSelectionSnapshot {
        try await SourceHostSelectionOperation.run { try await client.hostSelectionSnapshot() }
    }

    /// 固定到候选中的一个 Host，并让旧 Session 失效。
    func selectHost(baseURL: URL) async throws -> SourceHostSelectionSnapshot {
        try await SourceHostSelectionOperation.run { try await client.selectHost(baseURL: baseURL) }
    }
}
