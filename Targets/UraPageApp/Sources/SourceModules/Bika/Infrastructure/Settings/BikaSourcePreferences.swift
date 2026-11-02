import Foundation
import Synchronization

/// 哔咔本地偏好的默认值。
private enum BikaSourcePreferenceDefaults {
    /// 非阅读图片默认请求中等质量。
    static let browsingImageQuality: BikaImageQuality = .medium

    /// 图片 CDN 加速默认开启。
    static let usesImageCDNAcceleration = true
}

/// 保存哔咔来源本地偏好的进程内快照。
private struct BikaSourcePreferencesState: Sendable {
    var browsingImageQuality: BikaImageQuality
    var usesImageCDNAcceleration: Bool
}

/// 统一管理哔咔来源本地偏好的运行时状态与持久化。
///
/// 由 `BikaSourceClient` 持有唯一实例：API 拦截器与图片服务同步读取进程内值，
/// 设置页通过 Services 修改，页面不直接读写相同的 UserDefaults key。
final class BikaSourcePreferences: Sendable {
    private let state = Mutex(
        BikaSourcePreferencesState(
            browsingImageQuality: UserDefaults.standard.storedRawRepresentable(
                forKey: BikaConfiguration.Storage.browsingImageQuality,
                default: BikaSourcePreferenceDefaults.browsingImageQuality,
            ),
            usesImageCDNAcceleration: UserDefaults.standard.storedValue(
                forKey: BikaConfiguration.Storage.usesImageCDNAcceleration,
                default: BikaSourcePreferenceDefaults.usesImageCDNAcceleration,
            ),
        ),
    )

    /// 返回后续哔咔非阅读页面请求应使用的图片质量。
    func browsingImageQuality() -> BikaImageQuality {
        state.withLock { $0.browsingImageQuality }
    }

    /// 保存非阅读图片质量，并立即更新进程内快照。
    func selectBrowsingImageQuality(_ imageQuality: BikaImageQuality) {
        state.withLock { $0.browsingImageQuality = imageQuality }
        UserDefaults.standard.set(
            imageQuality.rawValue,
            forKey: BikaConfiguration.Storage.browsingImageQuality,
        )
    }

    /// 返回后续哔咔图片请求是否使用 go2778 CDN 加速。
    func usesImageCDNAcceleration() -> Bool {
        state.withLock { $0.usesImageCDNAcceleration }
    }

    /// 保存图片 CDN 加速偏好，并立即更新进程内快照。
    func selectUsesImageCDNAcceleration(_ isEnabled: Bool) {
        state.withLock { $0.usesImageCDNAcceleration = isEnabled }
        UserDefaults.standard.set(
            isEnabled,
            forKey: BikaConfiguration.Storage.usesImageCDNAcceleration,
        )
    }
}
