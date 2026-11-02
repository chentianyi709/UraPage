import UIKit

/// 弱引用 Reader 显示位图，不阻止 Kingfisher 按内存压力淘汰图片。
private final class ReaderCanvasImageReference {
    weak var image: UIImage?
}

/// 保存 Canvas 中一张页面的自身高度和短期显示状态。
struct ReaderCanvasNode {
    var page: ReaderPageSlot
    var aspectRatio: CGFloat?
    var imageDisplayMode: ReaderPageImageDisplayMode?
    var failure: ReaderPageFailure?
    var height: CGFloat = 0
    private let imageReference = ReaderCanvasImageReference()

    /// 返回仍由 Kingfisher 内存缓存、图片窗口或当前 ImageView 持有的显示位图。
    var image: UIImage? {
        get { imageReference.image }
        set { imageReference.image = newValue }
    }

    /// 图片窗口内强持有的动画显示对象（首帧位图 + 原始编码数据）。
    ///
    /// 动画图不写 Kingfisher 内存缓存：其成本只按首帧位图计，编码数据与
    /// CGImageSource 不计入 512 MiB 账面，按真实占用淘汰无法成立。
    /// 窗口内保留改由本字段承担，离开图片窗口即置空；静态图仍为弱引用，
    /// 由 Kingfisher 内存缓存按既有上限管理。
    var retainedAnimatedImage: UIImage?

    /// 使用章节与真实页序号作为节点标识。
    var id: ReaderPagePosition {
        page.identity
    }
}
