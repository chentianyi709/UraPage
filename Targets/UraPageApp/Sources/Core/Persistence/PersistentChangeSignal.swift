import Foundation
import SwiftData

/// 按实体名监听「这个实体的数据变了」。
///
/// 两个来源：普通写入靠 `ModelContext.save()` 自动发出的 `didSave`；批量写
/// （`ModelContext.delete(model:)`）不物化对象、**不会**发 `didSave`，由持久化层在提交后
/// 显式调用 `postBatchChange(entityName:)` 补一次。两者对订阅方是同一个语义：该实体变了，去重读。
enum PersistentChangeSignal {
    /// 参与变更通知的实体名。
    ///
    /// 从类型名取而不是在各调用点写裸字符串：模型改名时编译器会跟着报错，不会留下
    /// 「写方发了通知、读方监听的还是旧名字」这种只能靠 grep 发现的静默失效。
    enum Entity {
        static let readingProgress = String(describing: StoredReadingProgress.self)
        static let bookmark = String(describing: StoredBookmark.self)
        static let following = String(describing: StoredFollowing.self)
    }

    /// 批量写补发的通知名；与 `didSave` 分开，避免把「某个实体变了」广播成「全都变了」。
    private static let batchChangeName = Notification.Name("UraPage.PersistentChangeSignal.batch")
    private static let entityKey = "entityName"

    /// 批量写提交后显式广播一次。这是项目里唯一由写方主动发信号的场合，
    /// 因为框架在这种情况下不提供通知，而列表仍需跨页刷新。
    static func postBatchChange(entityName: String) {
        NotificationCenter.default.post(
            name: batchChangeName,
            object: nil,
            userInfo: [entityKey: entityName],
        )
    }

    /// 指定实体被插入、更新或删除时产出一次。
    static func changes(entityName: String) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let saveTask = Task {
                for await note in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                    guard touches(entityName, in: note) else {
                        continue
                    }

                    continuation.yield(())
                }
            }
            let batchTask = Task {
                for await note in NotificationCenter.default.notifications(named: batchChangeName) {
                    guard note.userInfo?[entityKey] as? String == entityName else {
                        continue
                    }

                    continuation.yield(())
                }
            }

            continuation.onTermination = { _ in
                saveTask.cancel()
                batchTask.cancel()
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
