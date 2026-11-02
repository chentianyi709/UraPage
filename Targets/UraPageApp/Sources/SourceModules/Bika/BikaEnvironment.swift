import SwiftUI

extension EnvironmentValues {
    /// 哔咔本源 Services 存储槽；写入用 `\.bikaServicesStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var bikaServicesStorage: BikaServices?

    /// 读取入口：本源稳定 Services；由 Module 的公共 root／destination／settingsSheet 边界安装。
    ///
    /// 页面用 `@Environment(\.bikaServices)` 读取，不再逐层接收 Services 参数；
    /// 取值缺失即装配错误（来源页面必须位于本源 Module 产出的页面边界内）。
    var bikaServices: BikaServices {
        guard let bikaServicesStorage else {
            preconditionFailure("bikaServices 未安装：哔咔页面必须由 BikaModule 安装本源 Environment 后展示")
        }

        return bikaServicesStorage
    }
}
