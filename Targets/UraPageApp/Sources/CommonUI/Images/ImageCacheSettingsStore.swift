import Foundation
import Observation
import SwiftUI

/// 通用设置里图片缓存分区的 owner（用户可变上限 + 运行期查询）。
///
/// 上限：读写持久化值（档位见 `BrowsingImageConfiguration` 的最小/最大/默认），
/// 并在共享图片缓存 owner 上立即生效。占用与清除委托给该 owner（同步磁盘 IO 由它离开调用方执行器）。
/// 这里只保留状态与字节数，展示文案与格式化由页面负责。
@MainActor
@Observable
final class ImageCacheSettingsStore {
    /// 当前磁盘缓存上限（字节）。
    private(set) var diskSizeLimitBytes: Int

    /// 当前占用状态；页面据此显示大小或加载／失败图标。
    private(set) var diskUsageState: StorageUsageState = .loading

    /// 正在清除缓存：期间禁用清除按钮。
    private(set) var isClearing = false

    /// 占用读取代次；只允许最后一次发起的结果回写，避免清除前后的并发读取把旧大小盖回来。
    @ObservationIgnored private var usageGeneration = 0

    @ObservationIgnored private let userDefaults = UserDefaults.standard
    @ObservationIgnored private let imageStore: BrowsingImageStore

    init(imageStore: BrowsingImageStore) {
        self.imageStore = imageStore
        let limit: Int = userDefaults.storedValue(
            forKey: AppConfiguration.Storage.imageCacheDiskSizeLimit,
            default: BrowsingImageConfiguration.defaultDiskSizeLimit,
        )
        diskSizeLimitBytes = limit
        // 启动即用持久化上限覆盖 owner 的默认值。
        imageStore.setDiskSizeLimit(bytes: limit)
    }

    /// 选择磁盘缓存上限：写回持久化值，并在图片缓存 owner 上生效。
    func selectDiskSizeLimit(bytes: Int) {
        diskSizeLimitBytes = bytes
        userDefaults.set(bytes, forKey: AppConfiguration.Storage.imageCacheDiskSizeLimit)
        imageStore.setDiskSizeLimit(bytes: bytes)
    }

    /// 读取当前占用；页面出现与清除完成后调用。
    ///
    /// 读取期间保留上一次的值（与旧项目一致，避免刷新时闪一下「计算中…」）；
    /// 只回写最后一次发起的结果，旧读取不能覆盖清除后的新大小。
    func refreshUsage() async {
        usageGeneration &+= 1
        let generation = usageGeneration

        do {
            let bytes = try await imageStore.totalDiskSize()
            guard generation == usageGeneration, !Task.isCancelled else { return }

            diskUsageState = .available(bytes: bytes)
        } catch {
            guard generation == usageGeneration, !Task.isCancelled else { return }

            AppLogger.warning("图片缓存占用读取失败", category: "App.Settings")
            diskUsageState = .failed
        }
    }

    /// 清空共享磁盘缓存并刷新占用，返回是否成功（失败的提示由页面负责）。
    ///
    /// 失败时也刷新占用：删了一半也要展示当前真实大小，不静默吞掉。
    @discardableResult
    func clearCache() async -> Bool {
        isClearing = true
        defer {
            isClearing = false
        }

        do {
            try await imageStore.clearDiskCache()
        } catch {
            AppLogger.warning("图片缓存清除失败", category: "App.Settings")
            await refreshUsage()
            return false
        }

        await refreshUsage()
        return true
    }
}

extension EnvironmentValues {
    /// 通用设置的图片缓存 owner 存储槽；写入用 `\.imageCacheSettingsStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var imageCacheSettingsStorage: ImageCacheSettingsStore?

    /// 读取入口：由 App 根视图安装，通用设置页读取，未安装即暴露装配错误。
    var imageCacheSettings: ImageCacheSettingsStore {
        guard let imageCacheSettingsStorage else {
            preconditionFailure("imageCacheSettings 未安装：读取通用设置必须位于 App 根边界内")
        }

        return imageCacheSettingsStorage
    }
}
