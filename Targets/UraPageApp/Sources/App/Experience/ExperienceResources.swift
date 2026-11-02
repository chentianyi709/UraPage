/// 一次来源激活期独占的体验资源；切源事务负责关闭并释放。
///
/// 图片工作域随本次激活创建，切源时只取消本体验的在途图片请求；
/// 全局共享内存池与共享磁盘都由 `BrowsingImageStore` 持有，不随体验释放。
@MainActor
final class ExperienceResources {
    /// 本次体验独占的普通图片工作域。
    let browsingImageScope: BrowsingImageScope

    /// ReaderSession 独占页面任务；这里只保留会话，供切源等待统一关闭。
    let readerSessions = ReaderSessionScope()

    init(imageStore: BrowsingImageStore) {
        browsingImageScope = imageStore.makeScope()
    }

    /// 切源事务：关闭图片工作域（取消在途工作；共享内存池与磁盘保留）。
    func close() async {
        await browsingImageScope.close()
    }
}
