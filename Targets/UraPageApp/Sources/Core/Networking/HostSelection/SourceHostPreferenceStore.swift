import Foundation

/// 持久化用户为某个来源选择的固定 Base URL；`nil` 表示尚未选择。
///
/// 只保存一个地址字符串，不保存候选或自动模式。
/// 候选地址只能来自代码或来源固定 bootstrap 入口，页面不能输入自定义 Host。
actor SourceHostPreferenceStore {
    private let userDefaults = UserDefaults.standard

    init() {}

    /// 读取已选 Base URL；缺失或无法解析时清除并返回 `nil`。
    func selectedBaseURL(for sourceID: ComicSourceID) -> URL? {
        let key = SourceConfiguration.Storage.hostSelection(for: sourceID)
        guard let stored = userDefaults.string(forKey: key) else {
            return nil
        }
        guard let url = URL(string: stored) else {
            userDefaults.removeObject(forKey: key)
            return nil
        }

        return url
    }

    /// 保存已选 Base URL；传入 `nil` 时清除选择。
    func setSelectedBaseURL(_ baseURL: URL?, for sourceID: ComicSourceID) {
        let key = SourceConfiguration.Storage.hostSelection(for: sourceID)
        guard let baseURL else {
            userDefaults.removeObject(forKey: key)
            return
        }

        userDefaults.set(baseURL.absoluteString, forKey: key)
    }
}
