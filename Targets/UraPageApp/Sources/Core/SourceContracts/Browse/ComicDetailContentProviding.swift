/// 定义具体漫画源详情模型向通用展示组件公开的最小公共内容。
///
/// 专属字段仍留在来源模型；使用公共详情展示组件时由来源详情实现本协议。
protocol ComicDetailContentProviding: Sendable {
    var identity: ComicIdentity { get }
    var title: String { get }
    var authorNames: [String] { get }
    /// 详情字段行：展示哪些字段、什么顺序由来源决定（浏览量、点赞、评分……），空数组时不显示字段。
    var fields: [ComicDetailField] { get }
    var summary: String { get }

    /// 详情页展示的标签组：组数与顺序由来源决定（分类、标签、角色……），空组由展示层跳过。
    var tagGroups: [ComicTagGroup] { get }

    var cover: ComicImageSource { get }
}
