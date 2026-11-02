import SwiftUI

extension EnvironmentValues {
    /// 绅士本源 Services 存储槽；写入用 `\.shenshiServicesStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var shenshiServicesStorage: ShenshiServices?

    /// 绅士列表筛选登记点存储槽；写入用 `\.shenshiListFilterHandoffStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var shenshiListFilterHandoffStorage: ShenshiListFilterHandoff?

    /// 读取入口：本源稳定 Services；由 Module 的公共 root／destination／settingsSheet 边界安装。
    ///
    /// 页面用 `@Environment(\.shenshiServices)` 读取，不再逐层接收 Services 参数；
    /// 取值缺失即装配错误（来源页面必须位于本源 Module 产出的页面边界内）。
    var shenshiServices: ShenshiServices {
        guard let shenshiServicesStorage else {
            preconditionFailure("shenshiServices 未安装：绅士页面必须由 ShenshiModule 安装本源 Environment 后展示")
        }

        return shenshiServicesStorage
    }

    /// 读取入口：列表筛选登记点；由 `ShenshiModule` 在体验根安装，发起方（当前是首页分区标题）写、更新页读，未安装即暴露装配错误。
    var shenshiListFilterHandoff: ShenshiListFilterHandoff {
        guard let shenshiListFilterHandoffStorage else {
            preconditionFailure("shenshiListFilterHandoff 未安装：绅士首页必须由 ShenshiModule 安装本源 Environment 后展示")
        }

        return shenshiListFilterHandoffStorage
    }
}
