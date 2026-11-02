import SwiftUI

/// 外部入口对某个列表页的筛选请求（如首页分区标题跳到列表页并带筛选）。
///
/// 目标页保留自己的页面身份（已加载数据、滚动位置、菜单状态），只把请求映射成本源的
/// 菜单选择再应用：`selectionID` 的语义由目标菜单的 `makeQuery` 决定，因此来源只需要
/// 把首页携带的值换算成菜单项 id（换算表由描述工厂提供）。
///
/// 一次请求可带多条菜单选择（如「排序回到第一个选项 + 指定分类」），它们在同一次查询变更里
/// 按数组顺序应用：列表只重新加载一次，菜单数据不重新请求，也不会出现中间查询的请求。
/// `token` 单调递增：同一序号只应用一次；应用后查询没有变化时不重载（重复请求同一筛选）。
nonisolated struct SourceListFilterRequest: Equatable, Sendable {
    /// 一条菜单选择：目标菜单的稳定 id + 菜单项 id。
    ///
    /// 用菜单 id 而不是 `menus` 数组位置：调整菜单顺序不会让外部筛选静默落到错误的菜单上。
    nonisolated struct Selection: Equatable, Sendable {
        let menuID: String
        let selectionID: String
    }

    /// 本次请求要应用的菜单选择；后面的选择基于前面选择的结果。
    let selections: [Selection]

    /// 请求序号。
    let token: Int
}

extension EnvironmentValues {
    /// 安装给目标列表页的外部筛选请求；由来源在本源 Tab 的根页面安装。
    @Entry var sourceListFilterRequest: SourceListFilterRequest?
}
