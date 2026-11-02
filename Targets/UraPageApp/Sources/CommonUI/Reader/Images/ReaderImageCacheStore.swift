import Foundation
import Kingfisher

/// 持有 App 进程内唯一的 Reader 图片缓存，并为每次阅读创建独立 lease。
final nonisolated class ReaderImageCacheStore: Sendable {
    let cache: ImageCache
    private let ownership: ReaderImageCacheOwnership

    /// 创建与普通图片缓存隔离的 Reader 专用缓存。
    init() {
        cache = ImageCache(name: AppConfiguration.ReaderImages.cacheName)
        cache.memoryStorage.config.totalCostLimit = AppConfiguration.ReaderImages.memoryCostLimit
        ownership = ReaderImageCacheOwnership(cache: cache)
    }

    /// 为一个 ReaderSession 创建独立的内存显示 ownership。
    func makeLease(sessionID: UUID) -> ReaderImageCacheLease {
        ReaderImageCacheLease(
            sessionID: sessionID,
            cache: cache,
            ownership: ownership,
        )
    }
}

/// 跟踪一个 ReaderSession 当前使用的内存显示变体。
final nonisolated class ReaderImageCacheLease: Sendable {
    let cache: ImageCache

    let sessionID: UUID
    private let ownership: ReaderImageCacheOwnership

    /// 绑定共享缓存和当前 ReaderSession identity。
    fileprivate init(
        sessionID: UUID,
        cache: ImageCache,
        ownership: ReaderImageCacheOwnership,
    ) {
        self.sessionID = sessionID
        self.cache = cache
        self.ownership = ownership
    }

    /// 在读取或写入内存显示变体前声明当前 session 的 ownership。
    func acquire(_ key: String) async {
        await ownership.acquire(key, for: sessionID)
    }

    /// 设置变化时只释放当前 session 对指定显示变体的 ownership。
    func release(_ keys: [String]) async {
        await ownership.release(keys, for: sessionID)
    }

    /// Reader 关闭时释放其全部 ownership，不影响其它 active session。
    func release() async {
        await ownership.releaseAll(for: sessionID)
    }
}

/// 集中维护共享内存项到 ReaderSession 的多对多引用关系。
private actor ReaderImageCacheOwnership {
    private let cache: ImageCache
    private var sessionsByKey: [String: Set<UUID>] = [:]
    private var keysBySession: [UUID: Set<String>] = [:]

    init(cache: ImageCache) {
        self.cache = cache
    }

    /// 幂等记录一个 session 正在使用指定内存项。
    func acquire(_ key: String, for sessionID: UUID) {
        sessionsByKey[key, default: []].insert(sessionID)
        keysBySession[sessionID, default: []].insert(key)
    }

    /// ownership 检查与内存删除在同一次 actor 调用完成，避免删除新 session 刚取得的图片。
    func release(_ keys: [String], for sessionID: UUID) {
        for key in keys {
            guard keysBySession[sessionID]?.remove(key) != nil else {
                continue
            }

            sessionsByKey[key]?.remove(sessionID)
            if sessionsByKey[key]?.isEmpty == true {
                sessionsByKey.removeValue(forKey: key)
                // Kingfisher 的纯内存删除同步完成，不需要 continuation 或 actor 挂起。
                cache.removeImage(forKey: key, fromMemory: true, fromDisk: false)
            }
        }
        if keysBySession[sessionID]?.isEmpty == true {
            keysBySession.removeValue(forKey: sessionID)
        }
    }

    /// 释放一个 ReaderSession 的全部 ownership。
    func releaseAll(for sessionID: UUID) {
        let keys = Array(keysBySession[sessionID] ?? [])
        release(keys, for: sessionID)
    }
}
