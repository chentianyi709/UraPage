import Foundation
import Observation
import SwiftUI

/// 通用设置里「阅读历史保留时间」的 owner。
///
/// 读取持久化档位、按选择写回；同时把档位推给阅读历史 store，
/// 并在启动与缩短周期时立即清理过期记录，避免历史无限增长占用储存。
@MainActor
@Observable
final class ReadingHistorySettingsStore {
    private(set) var retention: ReadingHistoryRetention

    @ObservationIgnored private let userDefaults = UserDefaults.standard
    @ObservationIgnored private let historyStore: ReadingHistoryStore

    init(historyStore: ReadingHistoryStore) {
        self.historyStore = historyStore
        let stored: Int? = userDefaults.storedValue(
            forKey: AppConfiguration.Storage.readingHistoryRetentionDays,
        )
        // 无法识别的持久化档位回退默认值，不以崩溃暴露损坏设置。
        let option = stored.flatMap(ReadingHistoryRetention.init(rawValue:)) ?? .defaultValue
        retention = option
        // 启动即按持久化档位清理一次过期历史。
        apply(option)
    }

    /// 选择保留时长：写回持久化值，并让历史 store 立即按新档位清理过期记录。
    func select(_ option: ReadingHistoryRetention) {
        guard option != retention else { return }

        retention = option
        userDefaults.set(option.rawValue, forKey: AppConfiguration.Storage.readingHistoryRetentionDays)
        apply(option)
    }

    /// 清除全部阅读历史（含继续阅读进度）；返回是否成功（失败提示由页面给出）。
    func clearAll() async -> Bool {
        do {
            try await historyStore.deleteAll()
            return true
        } catch {
            AppLogger.warning("阅读历史清除失败，errorType=\(type(of: error))", category: "Library.History")
            return false
        }
    }

    /// 同步档位到阅读历史 store，并触发一次过期清理。
    private func apply(_ option: ReadingHistoryRetention) {
        let days = option.dayCount
        Task { [historyStore] in
            await historyStore.setRetentionDays(days)
            try? await historyStore.pruneExpiredIfNeeded()
        }
    }
}

extension EnvironmentValues {
    /// 通用设置的阅读历史保留时间 owner 存储槽；写入用 `\.readingHistorySettingsStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var readingHistorySettingsStorage: ReadingHistorySettingsStore?

    /// 读取入口：由 App 根视图安装，通用设置页读取，未安装即暴露装配错误。
    var readingHistorySettings: ReadingHistorySettingsStore {
        guard let readingHistorySettingsStorage else {
            preconditionFailure("readingHistorySettings 未安装：读取通用设置必须位于 App 根边界内")
        }

        return readingHistorySettingsStorage
    }
}
