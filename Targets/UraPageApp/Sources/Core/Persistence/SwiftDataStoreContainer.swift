import Foundation
import SwiftData

/// 各持久化 owner 共用的独立库创建方式。
///
/// 阅读记录、搜索历史、书签收藏、下载四个库的规则完全一致：在 Application Support 下按
/// `AppConfiguration.Persistence` 声明的文件名各落一个独立库、不用 CloudKit、每个 owner
/// 独占一个 `@ModelActor`。规则只写在这里，改目录、改命名或换 CloudKit 时不用四处找。
enum SwiftDataStoreContainer {
    /// 创建一个独立 SwiftData 容器。
    ///
    /// - Parameters:
    ///   - schema: 该库包含的模型。
    ///   - name: `ModelConfiguration` 名称（同一进程内唯一，与库文件用途对应）。
    ///   - fileName: `AppConfiguration.Persistence` 里声明的库文件名。
    static func make(schema: Schema, name: String, fileName: String) throws -> ModelContainer {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true,
        )
        let url = directory.appending(
            path: fileName,
            directoryHint: .notDirectory,
        )
        let configuration = ModelConfiguration(
            name,
            schema: schema,
            url: url,
            cloudKitDatabase: .none,
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
