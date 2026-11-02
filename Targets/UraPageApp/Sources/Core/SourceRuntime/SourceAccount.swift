import Foundation
import Observation

/// 一次已验证登录的产物：要落盘的凭证 + 页面展示资料。
struct SourceAuthenticationResult<Credential: Sendable, Profile: Sendable>: Sendable {
    let credential: Credential
    let profile: Profile
}

/// 来源账号 owner 的公共实现（泛型）：登录收尾、退出与展示资料。
///
/// 只管三件事：**落盘展示资料、发布登录状态、退出**；登录请求本身由来源在自己的便利构造里
/// 以闭包提供（各来源的协议与验证顺序不同，例如哔咔需要先用候选 Token 验证 `users/profile`）。
/// 访问事实由 `SourceAccountAccessStore` 发布，来源把它与 Client 的 401 收口共享同一实例。
///
/// 顺序约定：资料先于登录状态就绪（门禁／账号页切到已登录内容时资料一定可读）；
/// 凭证写入失败则回滚资料，不留半份状态。
@MainActor
@Observable
final class SourceAccount<Credential: Codable & Sendable, Profile: Codable & Sendable> {
    /// 当前展示资料；未登录或资料缺失时为 `nil`。
    private(set) var profile: Profile?

    /// 访问事实（资料与凭证完整性 → 登录状态）。
    let access: SourceAccountAccessStore<Credential>

    @ObservationIgnored private let storageKey: String
    @ObservationIgnored private let userDefaults = UserDefaults.standard

    /// 凭证变化后让来源 Client 失效旧 Session；下次请求按新凭证重建。
    @ObservationIgnored private let credentialDidChange: @MainActor () async -> Void

    /// 来源自己的登录请求：只请求与解析，返回要落盘的凭证与资料。
    @ObservationIgnored private let requestLogin: @MainActor (
        _ account: String,
        _ password: String,
    ) async throws
        -> SourceAuthenticationResult<Credential, Profile>

    init(
        access: SourceAccountAccessStore<Credential>,
        storageKey: String,
        credentialDidChange: @escaping @MainActor () async -> Void,
        requestLogin: @escaping @MainActor (_ account: String, _ password: String) async throws
            -> SourceAuthenticationResult<Credential, Profile>,
    ) {
        self.access = access
        self.storageKey = storageKey
        self.credentialDidChange = credentialDidChange
        self.requestLogin = requestLogin
        profile = userDefaults.storedCodable(Profile.self, forKey: storageKey)

        // 资料和凭证共同组成登录状态；清理也由同一账号 owner 关联执行。
        access.configureProfileAvailability {
            [weak self] in self?.profile != nil
        }
        clearProfile: {
            [weak self] in self?.clearProfile()
        }
    }

    /// 登录：请求凭证与资料 → 落盘 → 让旧 Session 失效 → 发布已登录。
    func login(account: String, password: String) async throws {
        let authenticated = try await requestLogin(account, password)
        try Task.checkCancellation()

        let previousProfile = profile
        let previousStoredProfile = userDefaults.data(forKey: storageKey)

        try userDefaults.setCodable(authenticated.profile, forKey: storageKey)
        profile = authenticated.profile

        do {
            try await access.adopt(
                authenticated.credential,
                beforePublishing: credentialDidChange,
            )
        } catch {
            if let previousStoredProfile {
                userDefaults.set(previousStoredProfile, forKey: storageKey)
            } else {
                userDefaults.removeObject(forKey: storageKey)
            }
            profile = previousProfile
            throw error
        }
    }

    /// 退出登录：清除凭证与展示资料；返回是否成功（失败提示由页面给出）。
    @discardableResult
    func logout() async -> Bool {
        guard await access.signOut() else {
            return false
        }

        await credentialDidChange()
        return true
    }

    /// 凭证缺失、退出或认证失效时同步删除本源展示资料。
    private func clearProfile() {
        userDefaults.removeObject(forKey: storageKey)
        profile = nil
    }
}
