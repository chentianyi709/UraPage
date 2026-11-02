import SwiftUI

extension EnvironmentValues {
    /// 阅读历史 store 存储槽；写入用 `\.readingHistoryStoreStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var readingHistoryStoreStorage: ReadingHistoryStore?

    /// 来源运行时目录存储槽；写入用 `\.sourceRuntimeCatalogStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var sourceRuntimeCatalogStorage: SourceRuntimeCatalog?

    /// 读取入口：由 App 入口安装，未安装即暴露装配错误。
    var readingHistoryStore: ReadingHistoryStore {
        guard let readingHistoryStoreStorage else {
            preconditionFailure("ReadingHistoryStore 未由 App 入口安装")
        }

        return readingHistoryStoreStorage
    }

    /// 读取入口：由 App 入口安装，未安装即暴露装配错误。
    var sourceRuntimeCatalog: SourceRuntimeCatalog {
        guard let sourceRuntimeCatalogStorage else {
            preconditionFailure("SourceRuntimeCatalog 未由 App 入口安装")
        }

        return sourceRuntimeCatalogStorage
    }
}
