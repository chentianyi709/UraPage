import Foundation
import Observation
import SwiftUI

/// 通用设置「下载」分区的 owner：并发上限的持久化与下发。
///
/// 只保存用户可变值，默认值与可选范围来自 `AppConfiguration.Downloads`；写入后立即推给下载调度
/// owner：提高作品上限会补位排队作品，降低不打断在跑作品，页并发在下一批页生效。
@MainActor
@Observable
final class DownloadSettingsStore {
    /// 单来源同时下载的作品数。
    private(set) var workLimitPerSource: Int

    /// 单作品内并发处理的页数。
    private(set) var pageConcurrencyPerWork: Int

    @ObservationIgnored private let userDefaults: UserDefaults

    /// 下载调度 owner；由组合根在创建后接入，两者都是进程级唯一实例。
    @ObservationIgnored private var manager: DownloadManager?

    /// 最近一次下发任务；串行化连续修改，保证落地顺序与用户操作一致。
    @ObservationIgnored private var applyTask: Task<Void, Never>?

    init() {
        let userDefaults = UserDefaults.standard
        self.userDefaults = userDefaults
        workLimitPerSource = Self.clamp(
            userDefaults.storedValue(
                forKey: AppConfiguration.Storage.downloadWorkLimitPerSource,
                default: AppConfiguration.Downloads.defaultWorkLimitPerSource,
            ),
            to: AppConfiguration.Downloads.workLimitPerSourceRange,
        )
        pageConcurrencyPerWork = Self.clamp(
            userDefaults.storedValue(
                forKey: AppConfiguration.Storage.downloadPageConcurrencyPerWork,
                default: AppConfiguration.Downloads.defaultPageConcurrencyPerWork,
            ),
            to: AppConfiguration.Downloads.pageConcurrencyPerWorkRange,
        )
    }

    /// 接入调度 owner；组合根在创建它之后调用一次。
    func attach(manager: DownloadManager) {
        self.manager = manager
    }

    /// 选择单来源同时下载的作品数。
    func selectWorkLimitPerSource(_ value: Int) {
        let next = Self.clamp(value, to: AppConfiguration.Downloads.workLimitPerSourceRange)
        guard next != workLimitPerSource else { return }

        workLimitPerSource = next
        userDefaults.set(next, forKey: AppConfiguration.Storage.downloadWorkLimitPerSource)
        applyToManager()
    }

    /// 选择单作品内并发处理的页数。
    func selectPageConcurrencyPerWork(_ value: Int) {
        let next = Self.clamp(value, to: AppConfiguration.Downloads.pageConcurrencyPerWorkRange)
        guard next != pageConcurrencyPerWork else { return }

        pageConcurrencyPerWork = next
        userDefaults.set(next, forKey: AppConfiguration.Storage.downloadPageConcurrencyPerWork)
        applyToManager()
    }

    /// 把当前上限推给调度 owner；两者总是一起下发，避免中间态。
    ///
    /// 连续修改按顺序落地：后一次等前一次完成，旧值不会覆盖新值。
    private func applyToManager() {
        guard let manager else {
            // 组合根在创建后立即 attach；未接入说明装配顺序被改坏，不能静默丢设置。
            preconditionFailure("DownloadSettingsStore 未 attach DownloadManager")
        }

        let workLimit = workLimitPerSource
        let pageLimit = pageConcurrencyPerWork
        let previous = applyTask
        applyTask = Task {
            await previous?.value
            await manager.applyConcurrencyLimits(
                workLimitPerSource: workLimit,
                pageConcurrencyPerWork: pageLimit,
            )
        }
    }

    /// 把持久化值收口到当前范围：范围调整后旧值不会把调度停在非法档位。
    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension EnvironmentValues {
    /// 通用设置的下载并发 owner 存储槽；写入用 `\.downloadSettingsStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var downloadSettingsStorage: DownloadSettingsStore?

    /// 读取入口：由 App 根视图安装，通用设置页读取，未安装即暴露装配错误。
    var downloadSettings: DownloadSettingsStore {
        guard let downloadSettingsStorage else {
            preconditionFailure("downloadSettings 未安装：读取下载设置必须位于 App 根边界内")
        }

        return downloadSettingsStorage
    }
}
