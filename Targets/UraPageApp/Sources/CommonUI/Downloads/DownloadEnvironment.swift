import SwiftUI

/// 下载子系统在 App 入口安装的进程级环境值。
///
/// 声明放在 CommonUI：详情下载接线（CommonUI）与离线封面都读取这些值，
/// Features／SourceModules 只作为消费方，避免通用 UI 反向依赖上层目录。
extension EnvironmentValues {
    /// 进程级下载调度 owner 存储槽；写入用 `\.downloadManagerStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var downloadManagerStorage: DownloadManager?

    /// 下载资产 owner 存储槽；写入用 `\.downloadAssetStoreStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var downloadAssetStoreStorage: DownloadAssetStore?

    /// 读取入口：由 App 入口安装，未安装即暴露装配错误。
    var downloadManager: DownloadManager {
        guard let downloadManagerStorage else {
            preconditionFailure("DownloadManager 未由 App 入口安装")
        }

        return downloadManagerStorage
    }

    /// 读取入口：由 App 入口安装，供本地封面显示与离线读取，未安装即暴露装配错误。
    var downloadAssetStore: DownloadAssetStore {
        guard let downloadAssetStoreStorage else {
            preconditionFailure("downloadAssetStore 未由 App 入口安装")
        }

        return downloadAssetStoreStorage
    }
}
