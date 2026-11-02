/// 描述一个来源在进程内长期稳定的公共能力视图。
///
/// 由该来源的 Services 直接实现，引用稳定 Client；
/// 不保存页面数据、列表数组或图片解码缓存，也不包装第二个转发对象。
/// `SourceRuntimeCatalog` 与来源页面共享同一批 Services 实例：
/// 复制协议视图不等于重建 Client。
protocol ComicSourceRuntime: Sendable {
    /// 本源稳定标识；生命周期内固定，不随当前选中来源或路由改变。
    var sourceID: ComicSourceID { get }

    /// 返回本源无会话状态的章节入口；Reader 与下载共用此入口。
    func chapterContentService() -> any SourceChapterContentService

    /// 返回本源 Host 切换成功事件流；下载等跨来源 consumer 据此重启当前线路上的在途任务。
    func hostChangeStream() async -> AsyncStream<SourceHostChange>

    /// 在本源页面组合边界调用一次，创建页面级普通图片解析会话。
    ///
    /// 不在每个图片 cell 或 SwiftUI `body` 求值时重复创建；
    /// 返回的会话可以携带页面级快照（如画质），生命周期与页面一致。
    func makeBrowsingImages() -> any ComicImageService
}
