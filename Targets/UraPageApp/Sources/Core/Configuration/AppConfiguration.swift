/// App 层固定配置与持久化标识符。
///
/// 只放 App Target 自己的固定值与存储 Key；可变设置由对应 owner 负责读写，
/// 来源协议常量留在各来源的 `Configuration`，公共策略留在 `SourceConfiguration`。
/// 持久化命名空间前缀由 `AppIdentifierNamespace` 生成；版本段写在各 key 字符串里。
enum AppConfiguration {
    enum ReaderImages {
        static let cacheName = "UraPage.Reader"
        static let memoryCostLimit = 512 * 1024 * 1024
    }

    enum Persistence {
        /// 按在线／离线模式隔离进度的阅读记录数据库。
        static let readingHistoryStore = AppIdentifierNamespace.make("v1.reading-history.store")

        /// 搜索历史数据库（按来源隔离），与阅读记录分开。
        static let searchHistoryStore = AppIdentifierNamespace.make("v1.search-history.store")

        /// 下载章节记录与已下载作品的数据库。
        static let downloadStore = AppIdentifierNamespace.make("v1.downloads.store")

        /// 书签收藏（标签／作者／分类）数据库，与搜索历史、阅读记录分开。
        static let bookmarkStore = AppIdentifierNamespace.make("v1.bookmarks.store")
    }

    enum Downloads {
        /// 下载资产根目录名（Application Support 下）；目录内再按来源／作品／章节分层。
        static let assetsDirectory = AppIdentifierNamespace.make("v1.download-assets")

        /// 单来源同时下载的作品数：默认值与用户可选范围（运行时值由下载设置 owner 读写）。
        static let defaultWorkLimitPerSource = 3
        static let workLimitPerSourceRange = 1 ... 5

        /// 单作品内并发处理的页数：默认值与用户可选范围。
        static let defaultPageConcurrencyPerWork = 5
        static let pageConcurrencyPerWorkRange = 3 ... 8

        /// 全部作品共享的在途页任务名额；两个可调上限同时拉满时也不会超过它。
        static let maximumInFlightPageTasks = 48
    }

    enum SearchHistory {
        /// 每个来源最多保留的搜索历史条数。
        static let maxEntriesPerSource = 100
    }

    /// App 自己使用的持久化 Key。
    enum Storage {
        /// 用户最后选择的漫画源；切换成功时写入，启动时读取并恢复。
        static let selectedSource = AppIdentifierNamespace.make("v1.selected-source")

        /// 来源选择弹窗的用户排序；只影响展示顺序，不改变默认来源。
        static let sourceOrder = AppIdentifierNamespace.make("v1.source-order")

        /// 通用设置的主题模式（`ThemeMode` raw value）；由外观设置 owner 读写。
        static let themeMode = AppIdentifierNamespace.make("v1.theme-mode")

        /// 通用设置的「隐藏卡片副标题」（Bool）；由外观设置 owner 读写。
        static let hidesComicCardSubtitles = AppIdentifierNamespace.make("v1.hides-comic-card-subtitles")

        /// 三来源共用的章节弹窗列数；由界面偏好 owner 读写。
        static let chapterSheetColumnCount = AppIdentifierNamespace.make("v1.chapter-sheet-column-count")

        /// 通用设置的图片磁盘缓存上限（字节）；由图片缓存设置 owner 读写。
        static let imageCacheDiskSizeLimit = AppIdentifierNamespace.make("v1.image-cache-disk-size-limit")

        /// 通用设置的每来源同时下载作品数；由下载设置 owner 读写。
        static let downloadWorkLimitPerSource = AppIdentifierNamespace
            .make("v1.download-work-limit-per-source")

        /// 通用设置的单作品并发页数；由下载设置 owner 读写。
        static let downloadPageConcurrencyPerWork = AppIdentifierNamespace
            .make("v1.download-page-concurrency-per-work")

        /// 通用设置的阅读历史保留时长（`ReadingHistoryRetention` raw value）；由阅读历史设置 owner 读写。
        static let readingHistoryRetentionDays = AppIdentifierNamespace
            .make("v1.reading-history-retention-days")

        /// 在线 Reader 的显示偏好；与来源账号和阅读进度无关。
        static let readerThemeMode = AppIdentifierNamespace.make("v1.reader-theme-mode")
        static let readerChromeToggleMode = AppIdentifierNamespace.make("v1.reader-chrome-toggle-mode")
        static let disablesReaderSwipeBackWhenChromeHidden = AppIdentifierNamespace
            .make("v1.disables-reader-swipe-back-when-chrome-hidden")
    }
}
