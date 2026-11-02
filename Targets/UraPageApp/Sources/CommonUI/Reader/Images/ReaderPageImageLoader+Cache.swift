import Foundation
import Kingfisher
import UIKit

nonisolated extension ReaderPageImageLoader {
    /// 设置切换后只删除旧显示变体，不修改正式磁盘缓存。
    func releaseMemoryImages(
        for identities: [PageIdentity],
        displayMode: ReaderPageImageDisplayMode,
        pageAccess: ReaderPageAccess,
    ) async {
        var keys: [String] = []
        keys.reserveCapacity(identities.count)
        for identity in identities {
            let cacheKey = ReaderPageCacheKey.make(for: identity)
            let memoryCacheKey = Self.memoryCacheKey(
                cacheKey: cacheKey,
                displayMode: displayMode,
                sessionNamespace: pageAccess.sessionMemoryNamespace,
            )
            keys.append(memoryCacheKey)
        }
        await cacheLease.release(keys)
    }

    /// 只把静态显示变体放入 Kingfisher 内存引擎；动画图不写内存缓存。
    ///
    /// Kingfisher 对动画图只按首帧位图计费（编码数据与 CGImageSource 不计入 512 MiB 账面），
    /// 写池会让条目真实占用被低估、很难触发淘汰（GIF 密集阅读实测内存单调上涨）。
    /// 动画显示对象改由图片窗口强持有（`ReaderCanvasNode.retainedAnimatedImage`，离窗即释放）：
    /// 窗口内滚到直接命中；超出窗口回看时经「缓存优先」载荷入口重读
    /// （在线页命中磁盘缓存、不联网重下；离线页读本地资产）。
    func storeMemoryImage(
        _ image: UIImage,
        forKey key: String,
    ) {
        guard !image.isReaderAnimatedImage else {
            return
        }

        cache.store(
            image,
            forKey: key,
            toDisk: false,
        ) { _ in }
    }

    /// 为同一正式磁盘项生成仅存在于内存的显示变体 Key。
    static func memoryCacheKey(
        cacheKey: String,
        displayMode: ReaderPageImageDisplayMode,
        sessionNamespace: UUID?,
    ) -> String {
        if let sessionNamespace {
            return "reader.session.\(sessionNamespace.uuidString).\(cacheKey).display.\(displayMode.memoryCacheVariant)"
        }
        return "\(cacheKey).display.\(displayMode.memoryCacheVariant)"
    }
}
