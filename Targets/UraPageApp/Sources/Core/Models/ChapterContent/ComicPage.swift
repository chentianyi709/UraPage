/// 描述 Reader 与下载共同使用的一张有序漫画页。
///
/// 只保存稳定身份与零基序号，不暴露远程地址、Host、
/// 解扰参数或解码尺寸。
struct ComicPage: Identifiable, Hashable, Sendable {
    let identity: PageIdentity
    /// 本章内的零基序号；UI 展示页码时自行加一。
    let index: Int

    /// 使用完整页面身份作为列表稳定标识。
    var id: PageIdentity {
        identity
    }

    /// 创建一张不暴露来源处理细节的漫画页。
    init(identity: PageIdentity, index: Int) {
        self.identity = identity
        self.index = index
    }
}
