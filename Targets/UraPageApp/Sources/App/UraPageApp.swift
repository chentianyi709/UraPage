import Foundation
import SwiftUI

/// UraPage 应用入口。
@main
struct UraPageApp: App {
    /// 进程级组合根；App 启动即创建，来源 Services、Catalog 与图片磁盘缓存在此完成装配校验。
    @State private var dependencies = AppDependencies()

    init() {
        // 固定临时文件清理基准：早于任何 UI 交互与导出，避免启动任务被延迟时基准被推到用户操作之后。
        _ = TemporaryFiles.launchCutoff
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(
                model: dependencies.shellModel,
                host: dependencies.sourceHost,
                appearanceSettings: dependencies.appearanceSettings,
                imageCacheSettings: dependencies.imageCacheSettings,
                readingHistorySettings: dependencies.readingHistorySettings,
                downloadSettings: dependencies.downloadSettings,
            )
            // 进程级能力在入口统一安装，Shell 与其弹窗继承同一实例，不再逐项转发参数。
            // 对象仍由 AppDependencies 创建和持有；Reader 页面只创建自己的 session 与 lease。
            .environment(\.readerImageCacheStorage, dependencies.readerImageCache)
            .environment(\.imageMemoryPoolStorage, dependencies.imageMemoryPool)
            .environment(\.readerSettingsStorage, dependencies.readerSettings)
            .environment(\.downloadManagerStorage, dependencies.downloadManager)
            .environment(\.downloadAssetStoreStorage, dependencies.downloadAssetStore)
            .environment(\.readingHistoryStoreStorage, dependencies.readingHistory)
            .environment(\.readerProgressRecorderStorage, dependencies.readerProgressRecorder)
            .environment(\.searchHistoryStoreStorage, dependencies.searchHistory)
            .environment(\.bookmarkStoreStorage, dependencies.bookmarks)
            .environment(\.sourceRuntimeCatalogStorage, dependencies.catalog)
            // 统一 App 主题色：系统控件（加载圈、系统 Tab 选中态等）也使用品牌色，与旧版一致。
            .tint(Color.brandPrimary)
            // 启动任务：先订阅下载完成提示与各来源 Host 切换事件，再并行清理上次进程遗留的页传输／
            // 下载资产临时文件与执行下载对账；导出残留由设置页「清理其他数据」处理。
            // 清理只删除早于本次启动基准的文件，不会碰到对账新产生的临时文件。
            .task {
                dependencies.downloadToastNotifier.start()
                await dependencies.downloadManager.startHostChangeObservation()

                async let cleanup: Void = TemporaryFiles.removeStaleFiles()
                async let reconcile: Void = dependencies.downloadManager.reconcileAfterLaunch()
                _ = await (cleanup, reconcile)
            }
        }
    }
}
