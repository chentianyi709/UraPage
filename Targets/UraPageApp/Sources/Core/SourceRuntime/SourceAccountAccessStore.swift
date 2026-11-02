import Foundation
import Observation

/// 来源账号访问事实的唯一 owner：保存／恢复本源凭证并发布访问状态。
///
/// 只做「资料与凭证完整性 → 访问事实」这一件事：不解析凭证内容、不发登录请求、不决定错误文案、不承载页面状态；
/// 凭证由 `SourceCredentialRecord` 按 `sourceID` 隔离存放，日志分类与订阅者由来源与门禁使用。
/// 服务端拒绝认证（401）时由来源 Client 携带请求发起时的凭证代次调用
/// `invalidateAuthentication(rejectedGeneration:)`：只有代次仍匹配才清除凭证并发布未登录；
/// 删除失败时保留当前状态，避免「UI 未登录、请求却仍带凭证」。
@MainActor
@Observable
final class SourceAccountAccessStore<Credential: Codable & Sendable>: SourceAccessProvider {
    private(set) var current: SourceAccessSnapshot = .checking

    @ObservationIgnored private let credentials: SourceCredentialMutationStore<Credential>
    @ObservationIgnored private let logCategory: String

    /// 共享凭证任务：页面恢复和 Session 读取也等待登录／清理完成，不读取事务中间态。
    @ObservationIgnored private var credentialTask: Task<Credential?, any Error>?

    /// 账号操作代次：恢复、登录或清理时递增，旧结果不覆盖新状态。
    @ObservationIgnored private var generation = 0

    /// 订阅者；门禁走 Observation 观察 `current`，这里是给非 SwiftUI 消费者的同一份事实。
    @ObservationIgnored private var observers: [UUID: AsyncStream<SourceAccessSnapshot>.Continuation] = [:]

    /// 凭证代次：每次写入或删除开始时递增，供 Client 拒绝旧 Session 的迟到 401。
    @ObservationIgnored private(set) var credentialGeneration = 0

    /// 本地资料是否可读；由账号 owner 注入，用于维持「已登录 ⟹ 资料可读」。
    ///
    /// Keychain 有凭证但资料缺失（例如重装 App 保留 Keychain、清掉 UserDefaults，或登录收尾
    /// 只写入凭证）时，恢复出的访问事实不能是「已登录」，否则门禁会放行、账号页却拿不到资料。
    @ObservationIgnored private var isProfileAvailable: @MainActor () -> Bool = { true }
    @ObservationIgnored private var clearProfile: @MainActor () -> Void = {}

    init(
        credentials: SourceCredentialRecord<Credential>,
        logCategory: String,
    ) {
        self.credentials = SourceCredentialMutationStore(credentials: credentials)
        self.logCategory = logCategory
    }

    /// 由账号 owner 注入资料可读性检查；恢复访问事实时用它判定「已登录」是否成立。
    func configureProfileAvailability(
        _ provider: @escaping @MainActor () -> Bool,
        clearProfile: @escaping @MainActor () -> Void,
    ) {
        isProfileAvailable = provider
        self.clearProfile = clearProfile
    }

    /// 恢复本源账号；并发调用共享同一次恢复，已完成后不重复读取 Keychain。
    func ensureRestored() async {
        guard case .checking = current else {
            return
        }

        do {
            _ = try await credentialForSession()
        } catch {
            // 恢复任务已发布失败事实，页面通过 current 显示错误与重试入口。
        }
    }

    /// Session 与页面共享账号凭证任务；只能取得资料和凭证都存在的登录凭证。
    /// 登录与清理也占用同一任务，读取方等待事务完成，不能读取半份状态。
    /// 恢复／清理失败继续抛出，不能绕过失败事实直接读取 Keychain。
    func credentialForSession() async throws -> Credential? {
        if let credentialTask {
            return try await credentialTask.value
        }

        return try await startRestoration()
    }

    /// 恢复失败后的显式重试：丢弃上一次结果，重新走一次恢复。
    func retryRestoration() async {
        credentialTask?.cancel()
        credentialTask = nil
        do {
            _ = try await startRestoration()
        } catch {
            // 失败事实由恢复任务发布，保留显式重试入口。
        }
    }

    /// 订阅访问事实变化；订阅即先收到当前快照。
    ///
    /// TODO: 首个非 SwiftUI 消费者（Reader／下载的账号变化处理）接入时使用；
    /// 当前门禁直接观察 `current`，本方法暂无调用方。
    func updates() -> AsyncStream<SourceAccessSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield(current)

            let observerID = UUID()
            observers[observerID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.observers[observerID] = nil
                }
            }
        }
    }

    /// 登录成功后保存本源凭证、失效旧 Session，再发布已登录。
    ///
    /// 写入失败时抛出并保持当前状态（不留“已发布已登录、Keychain 却是空的”状态）。
    func adopt(
        _ credential: Credential,
        beforePublishing credentialDidChange: @escaping @MainActor () async -> Void,
    ) async throws {
        credentialTask?.cancel()
        generation += 1
        credentialGeneration += 1
        let operationGeneration = generation
        let mutationGeneration = credentialGeneration
        let credentials = credentials
        let task = Task<Credential?, any Error> {
            let didSave = try await credentials.save(credential, generation: mutationGeneration)
            guard didSave, operationGeneration == generation else {
                throw CancellationError()
            }

            // Session 读取共享此任务：凭证落盘、旧 Session 失效与状态发布完成后才返回新凭证。
            await credentialDidChange()
            guard operationGeneration == generation else {
                throw CancellationError()
            }

            commit(.authenticated, generation: operationGeneration)
            AppLogger.info("登录凭证已保存并发布已登录", category: logCategory)
            return credential
        }
        credentialTask = task
        do {
            _ = try await task.value
        } catch {
            if operationGeneration == generation {
                credentialTask = nil
            }
            throw error
        }
    }

    /// 用户主动退出：清除本地凭证并发布未登录；返回是否已清除（失败时保留当前状态）。
    ///
    /// 与 `invalidateAuthentication(rejectedGeneration:)` 走同一条清理与发布路径，差别只在日志语义。
    @discardableResult
    func signOut() async -> Bool {
        await clearCredential(logMessage: "已退出登录：凭证已清除并发布未登录")
    }

    /// 服务端拒绝认证：清除本地凭证并发布未登录（由来源 Client 判定后调用）。
    @discardableResult
    func invalidateAuthentication(rejectedGeneration: Int) async -> Bool {
        guard rejectedGeneration == credentialGeneration else {
            AppLogger.debug("忽略旧 Session 的认证拒绝", category: logCategory)
            return false
        }

        return await clearCredential(logMessage: "认证已失效：凭证已清除并发布未登录")
    }

    /// 清除凭证并发布未登录；删除失败时保留当前状态，避免「UI 未登录、请求却仍带凭证」。
    private func clearCredential(logMessage: String) async -> Bool {
        credentialTask?.cancel()
        generation += 1
        credentialGeneration += 1
        let operationGeneration = generation
        let mutationGeneration = credentialGeneration
        let credentials = credentials
        let logCategory = logCategory

        let task = Task<Credential?, any Error> {
            let didDelete = try await credentials.delete(generation: mutationGeneration)
            guard didDelete, operationGeneration == generation else {
                // 更新的账号操作已经接管最终状态；旧操作不能继续清资料或失效新 Session。
                throw CancellationError()
            }

            clearProfile()
            commit(.unauthenticated, generation: operationGeneration)
            AppLogger.info(logMessage, category: logCategory)
            return nil
        }
        credentialTask = task
        do {
            _ = try await task.value
            return true
        } catch is CancellationError {
            return false
        } catch {
            if operationGeneration == generation {
                credentialTask = nil
            }
            AppLogger.error(
                "凭证清除失败，保留当前状态，errorType=\(String(reflecting: type(of: error)))",
                category: logCategory,
            )
            return false
        }
    }

    /// 开始一次恢复：Keychain 是同步 IO，读取放到并发执行器，提交回到 MainActor。
    private func startRestoration() async throws -> Credential? {
        generation += 1
        let operationGeneration = generation
        current = .checking
        let credentials = credentials
        let logCategory = logCategory

        let task = Task<Credential?, any Error> { [weak self] in
            do {
                let credential = try await credentials.load()
                try Task.checkCancellation()
                guard let self, operationGeneration == generation else {
                    throw CancellationError()
                }

                if let credential, isProfileAvailable() {
                    commit(.authenticated, generation: operationGeneration)
                    return credential
                }

                // 两份登录数据缺一即失效：先清残留凭证，再清资料并发布未登录。
                if credential != nil {
                    credentialGeneration += 1
                    let didDelete = try await credentials.delete(generation: credentialGeneration)
                    try Task.checkCancellation()
                    guard didDelete, operationGeneration == generation else {
                        throw CancellationError()
                    }
                }
                clearProfile()
                commit(.unauthenticated, generation: operationGeneration)
                return nil
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // 凭证无法读取或解码属于本机问题：不猜测登录状态，也不说成服务端响应无效。
                AppLogger.error(
                    "账号凭证恢复失败，errorType=\(String(reflecting: type(of: error)))",
                    category: logCategory,
                )
                self?.commit(.failed(.credentialUnavailable), generation: operationGeneration)
                throw error
            }
        }

        credentialTask = task
        return try await task.value
    }

    /// 提交新事实并通知订阅者；旧代次或与当前相同的快照不重复提交。
    private func commit(_ snapshot: SourceAccessSnapshot, generation: Int) {
        guard generation == self.generation, snapshot != current else {
            return
        }

        current = snapshot

        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }
}

/// 串行执行一个来源的 Keychain 读写，并按 MainActor 分配的代次拒绝迟到变更。
///
/// Keychain API 是同步 IO；放在独立 actor 中既不阻塞 MainActor，也保证登录、退出和 401 清理
/// 不会按 IO 完成顺序互相覆盖。代次检查进一步保证调用进入 actor 的调度顺序不影响最终结果。
private actor SourceCredentialMutationStore<Credential: Codable & Sendable> {
    private let credentials: SourceCredentialRecord<Credential>
    private var latestMutationGeneration = 0

    init(credentials: SourceCredentialRecord<Credential>) {
        self.credentials = credentials
    }

    func load() throws -> Credential? {
        try credentials.load()
    }

    func save(_ credential: Credential, generation: Int) throws -> Bool {
        guard generation >= latestMutationGeneration else {
            return false
        }

        latestMutationGeneration = generation
        try credentials.save(credential)
        return true
    }

    func delete(generation: Int) throws -> Bool {
        guard generation >= latestMutationGeneration else {
            return false
        }

        latestMutationGeneration = generation
        try credentials.delete()
        return true
    }
}
