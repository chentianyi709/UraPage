import SwiftUI

extension EnvironmentValues {
    /// 一次来源体验的 Reader 资源会话集合存储槽；写入用 `\.readerSessionScopeStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var readerSessionScopeStorage: ReaderSessionScope?

    /// 读取入口：由来源体验根安装，未安装即暴露装配错误。
    var readerSessionScope: ReaderSessionScope {
        guard let readerSessionScopeStorage else {
            preconditionFailure("ReaderSessionScope 未由来源体验安装")
        }

        return readerSessionScopeStorage
    }
}

/// 一次来源体验内的 Reader 资源会话集合；跨来源 push 仍归发起体验，切源必须等待退出。
@MainActor
final class ReaderSessionScope {
    private var sessions: [UUID: ReaderSession] = [:]
    private(set) var isClosed = false

    func register(_ session: ReaderSession) {
        precondition(!isClosed, "不能向已关闭的来源体验注册 Reader")
        sessions[session.id] = session
    }

    /// 普通返回与切源共用 session 的幂等关闭任务；完成之前始终保留资源 owner。
    func close(_ session: ReaderSession) async {
        do {
            try await session.close()
            sessions[session.id] = nil
        } catch {
            AppLogger.error("Reader session 关闭失败：\(type(of: error))", category: "Reader.Session")
        }
    }

    func close() async {
        isClosed = true
        for session in Array(sessions.values) {
            await close(session)
        }
    }
}
