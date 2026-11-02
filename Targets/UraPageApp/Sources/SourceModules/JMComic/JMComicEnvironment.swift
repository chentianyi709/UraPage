import SwiftUI

extension EnvironmentValues {
    /// 禁漫本源 Services 存储槽；写入用 `\.jmComicServicesStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var jmComicServicesStorage: JMComicServices?

    /// 禁漫列表筛选登记点存储槽；写入用 `\.jmComicListFilterHandoffStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var jmComicListFilterHandoffStorage: JMComicListFilterHandoff?

    /// 读取入口：本源稳定 Services；由 Module 的公共 root／destination／settingsSheet 边界安装。
    ///
    /// 页面用 `@Environment(\.jmComicServices)` 读取，不再逐层接收 Services 参数；
    /// 取值缺失即装配错误（来源页面必须位于本源 Module 产出的页面边界内）。
    /// 类型是本源自己的 `JMComicServices`，不做类型擦除，页面拿到的就是可用的窄依赖。
    var jmComicServices: JMComicServices {
        guard let jmComicServicesStorage else {
            preconditionFailure("jmComicServices 未安装：禁漫页面必须由 JMComicModule 安装本源 Environment 后展示")
        }

        return jmComicServicesStorage
    }

    /// 读取入口：列表筛选登记点；由 `JMComicModule` 在体验根安装，发起方（当前是首页分区标题）写、分类页读，未安装即暴露装配错误。
    var jmComicListFilterHandoff: JMComicListFilterHandoff {
        guard let jmComicListFilterHandoffStorage else {
            preconditionFailure("jmComicListFilterHandoff 未安装：禁漫首页必须由 JMComicModule 安装本源 Environment 后展示")
        }

        return jmComicListFilterHandoffStorage
    }
}
