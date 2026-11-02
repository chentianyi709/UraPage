
/// 描述一次只执行一遍的 Canvas 页面定位命令。
struct ReaderCanvasScrollRequest: Equatable {
    let id: Int
    let pageID: ReaderPagePosition
}
