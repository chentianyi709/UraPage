import Foundation
import SwiftData

/// 按实体名监听 SwiftData 的保存通知。
///
/// 通知由 `ModelContext.save()` 自动发出，写入方不需要显式发送任何信号；
/// 页面收到后才决定要不要重读，避免切回分区时无脑查库。
///
/// 前提是写入走显式 `save()`（项目里的 persistence 层都是这样），
/// 依赖 autosave 的写入不会丢信号，但会延迟到系统保存时才到。
enum PersistentChangeSignal {
    /// 指定实体被插入、更新或删除时产出一次。
    static func changes(entityName: String) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await note in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                    guard touches(entityName, in: note) else {
                        continue
                    }

                    continuation.yield(())
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 本次保存是否动到了指定实体。
    ///
    /// 明细拿不到（`userInfo` 缺失、键类型或值类型与预期不同）时按「有变化」处理：
    /// 多读一次的代价远小于漏掉一次真正写入、让列表停在旧数据上。
    private static func touches(_ entityName: String, in note: Notification) -> Bool {
        guard let userInfo = note.userInfo else {
            return true
        }

        // 键可能以枚举或原始字符串写入，两种都试。
        let keys: [AnyHashable] = [
            ModelContext.NotificationKey.insertedIdentifiers,
            ModelContext.NotificationKey.updatedIdentifiers,
            ModelContext.NotificationKey.deletedIdentifiers,
            ModelContext.NotificationKey.insertedIdentifiers.rawValue,
            ModelContext.NotificationKey.updatedIdentifiers.rawValue,
            ModelContext.NotificationKey.deletedIdentifiers.rawValue,
        ]

        var sawIdentifiers = false
        for key in keys {
            guard let identifiers = userInfo[key] as? Set<PersistentIdentifier> else {
                continue
            }

            sawIdentifiers = true
            if identifiers.contains(where: { $0.entityName == entityName }) {
                return true
            }
        }

        return !sawIdentifiers
    }
}
