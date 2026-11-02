/// 禁漫「首页分区标题 → 分类页」的跳转登记：待消费筛选的值是服务端给出的分类 slug。
///
/// 登记与消费流程见 `SourceListFilterHandoff`；本文件只声明本源的筛选值类型与旧版的有效性规则。
typealias JMComicListFilterHandoff = SourceListFilterHandoff<String>

extension SourceListFilterHandoff where Value == String {
    /// 登记一次分类页跳转；空 slug（服务端没有给出可请求值）被忽略。
    func requestCategory(slug: String) {
        guard !slug.isEmpty else {
            return
        }

        request(slug)
    }
}
