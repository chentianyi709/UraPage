/// App 进程级依赖的唯一 owner（composition root）。
///
/// App 启动时创建一次：在这里装配三个编译期来源的稳定 Services，并由同一批实例建立
/// 跨来源能力视图与各来源的体验 Module。这些能力在切源时保留，不做全局可变单例，
/// 也不向页面逐层传递本对象。
///
/// 不依赖其它依赖的对象直接写成属性默认值（初始化顺序早于 `init` 体，可直接被后面的装配读到）；
/// 需要别的实例或会抛错的（catalog、图片缓存、宿主、调度器、记录器）才在 `init` 里按依赖顺序构造。
@MainActor
final class AppDependencies {
    /// 跨来源能力视图，供下载、混合书架、Reader 入口等真实跨源 consumer 使用。
    let catalog: SourceRuntimeCatalog

    /// 进程内唯一的普通图片磁盘缓存 owner（Kingfisher 细节封装在 CommonUI）。
    private let browsingImageStore: BrowsingImageStore

    /// 非阅读图片的共享内存池（浏览图片与已下载封面共用）；由图片缓存 owner 持有。
    var imageMemoryPool: ImageMemoryPool {
        browsingImageStore.memoryPool
    }

    /// 已装配的来源宿主；Shell 无需知道各来源 Module。
    let sourceHost: AppSourceHost

    /// App Shell 状态（当前来源体验与切源事务）的进程级唯一 owner。
    let shellModel: AppShellModel

    /// 通用设置的外观偏好 owner（主题模式）；App 根视图应用、通用设置页修改。
    let appearanceSettings = AppearanceSettingsStore()

    /// 通用设置的图片缓存 owner（磁盘上限 + 占用/清除）；在图片缓存 store 创建后构造并应用持久化上限。
    let imageCacheSettings: ImageCacheSettingsStore

    /// 进程级 Reader 图片缓存；每个阅读页面仍使用独立 lease。
    let readerImageCache = ReaderImageCacheStore()

    /// 进程级下载调度 owner；资产与记录分别由资产库 actor 与持久化 actor 管理。
    let downloadManager: DownloadManager

    /// 通用设置的下载并发 owner；创建调度 owner 时提供初始值，之后负责下发修改。
    let downloadSettings = DownloadSettingsStore()

    /// 下载封面与章节资产的唯一文件 owner；由下载记录封面与离线 Reader 共用。
    let downloadAssetStore = DownloadAssetStore()

    /// 下载完成提示订阅者；启动时订阅下载变更流并在完成时弹 Toast。
    let downloadToastNotifier: DownloadToastNotifier

    let readerSettings = ReaderSettingsStore()

    /// 三来源共用的新格式阅读记录；进度写入由 ReaderProgressRecorder 串行化。
    let readingHistory = ReadingHistoryStore()
    let readerProgressRecorder: ReaderProgressRecorder

    /// 通用设置的阅读历史保留时间 owner（启动与修改时清理过期历史）。
    let readingHistorySettings: ReadingHistorySettingsStore

    /// 搜索历史入口（按来源隔离，独立 SwiftData 库）。
    let searchHistory = SearchHistoryStore()

    /// 书签收藏入口（标签／作者／分类，跨来源，独立 SwiftData 库）。
    let bookmarks = BookmarkStore()

    init() {
        // 具体来源的创建只在各来源 Module 维护，新增来源不再修改组合根的参数清单。
        // Module 仅在启动时构造一次，UI 与 Catalog 继续共享同一批 Services。
        let plugins = AppSourceRegistrations.make()

        // 注册校验失败代表编译期来源没有全部装配，属程序错误：直接暴露，不兜底也不面向用户。
        do {
            catalog = try SourceRuntimeCatalog(runtimes: plugins.map(\.runtime))
        } catch {
            preconditionFailure("来源装配校验失败：\(error)")
        }

        // 磁盘缓存是 App 级基础设施，创建失败同样属于无法继续运行的装配错误。
        do {
            browsingImageStore = try BrowsingImageStore()
        } catch {
            preconditionFailure("图片磁盘缓存创建失败：\(error)")
        }

        let sourceHost = AppSourceHost(plugins: plugins, imageStore: browsingImageStore)
        self.sourceHost = sourceHost
        shellModel = AppShellModel(host: sourceHost)
        imageCacheSettings = ImageCacheSettingsStore(imageStore: browsingImageStore)

        downloadManager = DownloadManager(
            catalog: catalog,
            assetStore: downloadAssetStore,
            browsingImageCache: browsingImageStore,
            cacheReading: ReaderChapterImageCache(store: readerImageCache),
            workLimitPerSource: downloadSettings.workLimitPerSource,
            pageConcurrencyPerWork: downloadSettings.pageConcurrencyPerWork,
        )
        downloadSettings.attach(manager: downloadManager)
        downloadToastNotifier = DownloadToastNotifier(manager: downloadManager)

        readingHistorySettings = ReadingHistorySettingsStore(historyStore: readingHistory)
        readerProgressRecorder = ReaderProgressRecorder(store: readingHistory)

        AppLogger.debug(
            "来源装配完成：\(plugins.map(\.descriptor.sourceID.rawValue).joined(separator: "、"))",
            category: "App.Startup",
        )
    }
}
