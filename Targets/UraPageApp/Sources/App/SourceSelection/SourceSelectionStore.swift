import Foundation

/// 持久化用户最后选择的漫画源与来源列表顺序。
///
/// 只保存来源 ID：切换成功或排序完成时立即写入，不依赖 App 退出回调；
/// 当前选择与展示顺序独立存储，默认来源仍由 App Shell 按注册顺序决定。
@MainActor
struct SourceSelectionStore {
    private let userDefaults = UserDefaults.standard

    /// 返回上次选择的来源；没有保存过或值已无法识别时返回 `nil`。
    func selectedSource() -> ComicSourceID? {
        guard let rawValue: String = userDefaults
            .storedValue(forKey: AppConfiguration.Storage.selectedSource),
            let sourceID = ComicSourceID(rawValue: rawValue)
        else {
            return nil
        }

        return sourceID
    }

    /// 保存当前选择的来源。
    func save(_ sourceID: ComicSourceID) {
        userDefaults.set(sourceID.rawValue, forKey: AppConfiguration.Storage.selectedSource)
    }

    /// 恢复用户排序；未保存过时返回空数组，已移除的来源不再参与展示。
    func sourceOrder() -> [ComicSourceID] {
        let rawValues: [String] = userDefaults.storedValue(forKey: AppConfiguration.Storage.sourceOrder) ?? []
        return rawValues.compactMap(ComicSourceID.init(rawValue:))
    }

    /// 拖动完成后保存完整来源顺序，与当前选中的来源独立存储。
    func saveSourceOrder(_ sourceIDs: [ComicSourceID]) {
        userDefaults.set(sourceIDs.map(\.rawValue), forKey: AppConfiguration.Storage.sourceOrder)
    }
}
