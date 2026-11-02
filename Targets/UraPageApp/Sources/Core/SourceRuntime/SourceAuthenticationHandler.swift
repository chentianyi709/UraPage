import Foundation

/// 认证失效收口的公共入口：来源 Client 在请求失败时调用
/// `handle(_:credentialGeneration:)`。
///
/// 只把「服务端明确拒绝认证」（HTTP 401 → `ComicSourceError.authenticationRequired`）这一种失败
/// 收敛成「通知账号 owner 清凭证并发布未登录」；让携带旧凭证的 Session 失效属于 Client 自己的状态，
/// 由调用方在 `handle(_:credentialGeneration:)` 返回 `true` 后处理，因此这里不持有 Client，
/// 组合根不会出现互相依赖。
struct SourceAuthenticationHandler: Sendable {
    /// 读取当前凭证代次；每次凭证写入或删除开始时递增。
    private let currentCredentialGeneration: @Sendable () async -> Int

    /// 通知本源账号 owner；只有被拒请求使用的凭证代次仍然有效时才清理。
    private let notifyAccountOwner: @Sendable (_ rejectedGeneration: Int) async -> Bool

    /// 三来源复用同一账号事实 owner 的绑定方式，避免每个 Services 重写两个转发闭包。
    @MainActor
    init(access: SourceAccountAccessStore<some Codable & Sendable>) {
        currentCredentialGeneration = { await access.credentialGeneration }
        notifyAccountOwner = { await access.invalidateAuthentication(rejectedGeneration: $0) }
    }

    /// 请求发起前取得凭证代次；失败收口时用它拒绝旧 Session 的迟到 401。
    func credentialGeneration() async -> Int {
        await currentCredentialGeneration()
    }

    /// 是当前凭证的认证失效则通知账号 owner 并返回 `true`。
    ///
    /// 旧 Session 在换账号后迟到的 401 返回 `false`，不能删除刚写入的新凭证。
    @discardableResult
    func handle(_ error: any Error, credentialGeneration: Int) async -> Bool {
        guard SourceNetworkErrorMapper.isAuthenticationRejection(error) else {
            return false
        }

        return await notifyAccountOwner(credentialGeneration)
    }
}
