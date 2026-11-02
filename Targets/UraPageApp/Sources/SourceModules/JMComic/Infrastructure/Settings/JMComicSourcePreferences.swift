import Foundation
import Synchronization

/// 禁漫本地偏好的默认值。
private enum JMComicSourcePreferenceDefaults {
    /// 内容语言默认繁体中文。
    static let contentLanguage: JMComicContentLanguage = .traditionalChinese

    /// 分类参数默认转换为繁体中文。
    static let usesTraditionalCategoryParameter = true
}

/// 保存禁漫来源本地偏好的进程内快照。
private struct JMComicSourcePreferencesState: Sendable {
    var contentLanguage: JMComicContentLanguage
    var usesTraditionalCategoryParameter: Bool
}

/// 统一管理禁漫来源本地偏好的运行时状态与持久化。
///
/// 由 `JMComicSourceClient` 持有唯一实例：请求拦截器同步读取进程内值，
/// 设置页通过 Services 修改，页面不直接读写相同的 UserDefaults key。
/// 创建时恢复已保存值；修改同时更新进程内快照与持久化。
final class JMComicSourcePreferences: Sendable {
    private let state = Mutex(
        JMComicSourcePreferencesState(
            contentLanguage: UserDefaults.standard.storedRawRepresentable(
                forKey: JMComicConfiguration.Storage.contentLanguage,
                default: JMComicSourcePreferenceDefaults.contentLanguage,
            ),
            usesTraditionalCategoryParameter: UserDefaults.standard.storedValue(
                forKey: JMComicConfiguration.Storage.usesTraditionalCategoryParameter,
                default: JMComicSourcePreferenceDefaults.usesTraditionalCategoryParameter,
            ),
        ),
    )

    /// 返回后续禁漫 GET 请求应使用的内容语言。
    func contentLanguage() -> JMComicContentLanguage {
        state.withLock { $0.contentLanguage }
    }

    /// 保存内容语言，并更新供请求拦截器同步读取的进程内值。
    func selectContentLanguage(_ language: JMComicContentLanguage) {
        state.withLock { $0.contentLanguage = language }
        UserDefaults.standard.set(language.rawValue, forKey: JMComicConfiguration.Storage.contentLanguage)
    }

    /// 返回分类接口是否把分类名转换为繁体中文。
    func usesTraditionalCategoryParameter() -> Bool {
        state.withLock { $0.usesTraditionalCategoryParameter }
    }

    /// 保存分类参数转换偏好，并立即更新进程内值。
    func selectUsesTraditionalCategoryParameter(_ isEnabled: Bool) {
        state.withLock { $0.usesTraditionalCategoryParameter = isEnabled }
        UserDefaults.standard.set(
            isEnabled,
            forKey: JMComicConfiguration.Storage.usesTraditionalCategoryParameter,
        )
    }
}
