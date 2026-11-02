/// 描述绅士推荐分区已经脱离 HTML 链接字符串的导航语义。
enum ShenshiHomeSectionNavigation: Hashable, Sendable {
    /// 切换到更新页；`nil` 表示服务端的全部更新。
    case updates(categoryID: Int?)

    /// 当前分区没有可识别的分类跳转。
    case none
}

/// 保存绅士推荐页的一个服务端分区及其固定展示漫画。
struct ShenshiHomeSection: Identifiable, Hashable, Sendable {
    /// 使用来源分区标题作为当前页面的稳定标识。
    let id: String

    /// 转换为简体中文后的分区标题。
    let title: String

    /// 按网页顺序解析成功的前六个漫画；静态分区不做去重。
    let items: [ComicListItem]

    /// 由 Source Target 从分区标题链接解析出的 typed 导航语义。
    let navigation: ShenshiHomeSectionNavigation
}
