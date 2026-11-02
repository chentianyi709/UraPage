/// 绅士「首页分区标题 → 更新页」的跳转登记：待消费筛选的值是分类 id（`nil` 表示「全部」）。
///
/// 登记与消费流程见 `SourceListFilterHandoff`；本文件只声明本源的筛选值类型与旧版的有效性规则。
typealias ShenshiListFilterHandoff = SourceListFilterHandoff<Int?>

extension SourceListFilterHandoff where Value == Int? {
    /// 登记一次更新页跳转；`nil` 表示「全部」，非正数（旧版视为无效的分类 id）被忽略。
    func requestUpdates(categoryID: Int?) {
        guard categoryID.map({ $0 > 0 }) ?? true else {
            return
        }

        request(categoryID)
    }
}
