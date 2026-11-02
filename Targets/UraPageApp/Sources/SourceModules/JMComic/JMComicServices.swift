import Foundation

/// 禁漫来源模块的唯一公开入口，共享同一个稳定 Source Client。
///
/// 已暴露浏览、详情、点赞、图片、章节、Host 与账号（登录/退出/资料）能力。
/// TODO: 收藏同步、评论属于后续层。
struct JMComicServices: ComicSourceRuntime, SourceHostSettingsProviding, Sendable {
    let sourceID = ComicSourceID.jm

    /// 本源唯一账号 owner：登录/退出、展示资料与门禁读取的访问事实。
    let account: JMComicAccount

    private let chapterContent: JMComicChapterContentService
    private let client: JMComicSourceClient

    /// 由本源 Module 创建稳定禁漫 Client。
    ///
    /// `@MainActor`：账号 owner 是 MainActor 隔离的，组合根只在 MainActor 装配一次。
    @MainActor
    init() {
        let discovery = JMComicHostDiscovery()
        let hostProvider = SourceHostProvider(sourceID: .jm) {
            try await discovery.discoverCandidates()
        }

        let access = JMComicAccountAccessStore()
        // 认证失效（401）由 Client 判定并通知账号 owner 清凭证、发布未登录；Client 不直接写 Keychain。
        let client = JMComicSourceClient(
            hostProvider: hostProvider,
            access: access,
        )
        self.client = client
        account = JMComicAccount(client: client, access: access)
        chapterContent = JMComicChapterContentService(client: client)
    }

    func chapterContentService() -> any SourceChapterContentService {
        chapterContent
    }

    /// 转发禁漫 Client 的 Host 切换成功事件；下载据此重启本源当前线路上的在途章节。
    func hostChangeStream() async -> AsyncStream<SourceHostChange> {
        await client.hostChangeStream()
    }

    /// 登录禁漫账号；成功后凭证与资料由账号 owner 落盘并发布已登录。
    func login(username: String, password: String) async throws {
        try await SourceServiceOperation.run(failureMessage: "账号登录失败", category: "JM.Account") {
            try await account.login(account: username, password: password)
        }
    }

    /// 退出禁漫账号：清除凭证与展示资料；返回是否成功（失败提示由页面给出）。
    @discardableResult
    func logout() async -> Bool {
        await account.logout()
    }

    /// 页面组合边界工厂：每次返回新的页面级图片会话（禁漫无页面快照，仍需按契约新建）。
    func makeBrowsingImages() -> any ComicImageService {
        SourceBrowsingImageService(source: JMComicBrowsingImageSource(client: client))
    }

    /// 获取禁漫首页当前可展示的推广分区。
    func homeSections() async throws -> [JMComicHomeSection] {
        try await SourceServiceOperation.run(failureMessage: "首页加载失败", category: "JM.Home") {
            try await client.homeSections()
        }
    }

    /// 获取首页顶部的随机推荐漫画。
    func randomRecommendComics() async throws -> [ComicListItem] {
        try await SourceServiceOperation.run(failureMessage: "随机推荐加载失败", category: "JM.Home") {
            try await client.randomRecommendComics()
        }
    }

    /// 获取首页一个普通推广分区的一页漫画。
    func promotionComics(
        sectionID: String,
        page: Int,
    ) async throws -> JMComicPromotionComicPage {
        try await SourceServiceOperation.run(
            failureMessage: "推广列表加载失败，sectionID=\(sectionID)，page=\(page)",
            category: "JM.Promotion",
        ) {
            try await client.promotionComics(sectionID: sectionID, page: page)
        }
    }

    /// 获取禁漫指定页的最新漫画，并给出下一页规则。
    func latest(page: Int = 0) async throws -> ComicPageSlice<Int> {
        try await SourceServiceOperation.run(failureMessage: "最新页加载失败，page=\(page)", category: "JM.Latest") {
            try await client.latest(page: page)
        }
    }

    /// 获取禁漫指定筛选下的一页周刊漫画。
    func weeklyComics(
        type: JMComicWeeklyContentType,
        date: JMComicWeeklyDate,
        page: Int,
    ) async throws -> JMComicWeeklyComicPage {
        try await SourceServiceOperation.run(
            failureMessage: "周刊加载失败，type=\(type.rawValue)，date=\(date.rawValue)，page=\(page)",
            category: "JM.Weekly",
        ) {
            try await client.weeklyComics(type: type, date: date, page: page)
        }
    }

    /// 获取禁漫分类页的一级和二级菜单。
    func categories() async throws -> [JMComicCategory] {
        try await SourceServiceOperation.run(failureMessage: "分类菜单加载失败", category: "JM.Categories") {
            try await client.categories()
        }
    }

    /// 获取禁漫指定筛选下的一页漫画。
    func categoryComics(
        category: JMComicCategorySelection,
        sort: JMComicSort,
        page: Int,
    ) async throws -> [ComicListItem] {
        try await SourceServiceOperation.run(
            failureMessage: "分类结果加载失败，sort=\(sort.rawValue)，page=\(page)",
            category: "JM.Categories",
        ) {
            try await client.categoryComics(category: category.requestSlug, sort: sort, page: page)
        }
    }

    /// 使用禁漫搜索接口获取固定关键词的一页漫画。
    func searchComics(
        query: String,
        sort: JMComicSearchSort,
        searchType: JMComicSearchType = .site,
        dateFilter: JMComicSearchDateFilter? = nil,
        page: Int,
    ) async throws -> JMComicSearchComicPage {
        try await SourceServiceOperation.run(
            failureMessage: "搜索结果加载失败，sort=\(sort.rawValue)，page=\(page)",
            category: "JM.Search",
        ) {
            try await client.searchComics(
                query: query,
                sort: sort,
                searchType: searchType,
                dateFilter: dateFilter,
                page: page,
            )
        }
    }

    /// 读取搜索页的热门搜索词；无需登录，失败只影响推荐区。
    func searchHotTags() async throws -> [String] {
        try await SourceServiceOperation.run(
            failureMessage: "热门搜索加载失败",
            category: "JM.Search",
        ) {
            try await client.hotTags()
        }
    }

    /// 获取禁漫漫画详情；身份是否属于本源由跨来源入口校验一次，这里不重复判断。
    func detail(for identity: ComicIdentity) async throws -> JMComicDetail {
        try await SourceServiceOperation.run(
            failureMessage: "漫画详情加载失败，id=\(identity.comicID)",
            category: "JM.Detail",
        ) {
            try await client.detail(comicID: identity.comicID)
        }
    }

    /// 为禁漫作品提交一次不可撤销的点赞；不要求登录，服务端业务结果原样返回。
    func likeComic(_ identity: ComicIdentity) async throws -> JMComicLikeResult {
        try await SourceServiceOperation.run(
            failureMessage: "漫画点赞失败，id=\(identity.comicID)",
            category: "JM.Like",
        ) {
            try await client.likeComic(comicID: identity.comicID)
        }
    }

    /// 返回禁漫 GET 请求当前使用的内容语言（请求拦截器按它补 `lang` 参数）。
    func selectedContentLanguage() -> JMComicContentLanguage {
        client.selectedContentLanguage()
    }

    /// 切换内容语言：更新偏好并用新语言重新请求远程 Setting；失败回滚。
    func selectContentLanguage(_ language: JMComicContentLanguage) async throws {
        try await SourceServiceOperation.run(
            failureMessage: "内容语言切换失败，language=\(language.rawValue)",
            category: "JM.Settings",
        ) {
            try await client.selectContentLanguage(language)
        }
    }

    /// 返回分类接口是否把分类名转换为繁体中文（请求拦截器按它决定分类参数）。
    func selectedUsesTraditionalCategoryParameter() -> Bool {
        client.selectedUsesTraditionalCategoryParameter()
    }

    /// 保存分类参数转换偏好并立即生效：之后的分类请求使用新参数。
    @discardableResult
    func selectUsesTraditionalCategoryParameter(_ isEnabled: Bool) -> Bool {
        client.selectUsesTraditionalCategoryParameter(isEnabled)
    }

    /// 返回禁漫远程 Setting 里的图源候选、当前选择与实际图片 Host。
    func imageSourceSelectionSnapshot() async throws -> JMComicImageSourceSelectionSnapshot {
        try await SourceServiceOperation.run(failureMessage: "图源列表加载失败", category: "JM.Settings") {
            try await client.imageSourceSelectionSnapshot()
        }
    }

    /// 提交图源切换；Client 复用当前 Session 请求并更新 Setting，成功后返回新的快照。
    func selectImageSource(_ key: Int) async throws -> JMComicImageSourceSelectionSnapshot {
        try await SourceServiceOperation.run(
            failureMessage: "图源切换失败，key=\(key)",
            category: "JM.Settings",
        ) {
            try await client.selectImageSource(key)
        }
    }

    /// 返回禁漫当前候选地址与实际地址。
    func hostSelectionSnapshot() async throws -> SourceHostSelectionSnapshot {
        try await SourceHostSelectionOperation.run { try await client.hostSelectionSnapshot() }
    }

    /// 固定到候选中的一个 Host，并让旧 Session 失效。
    func selectHost(baseURL: URL) async throws -> SourceHostSelectionSnapshot {
        try await SourceHostSelectionOperation.run { try await client.selectHost(baseURL: baseURL) }
    }
}
