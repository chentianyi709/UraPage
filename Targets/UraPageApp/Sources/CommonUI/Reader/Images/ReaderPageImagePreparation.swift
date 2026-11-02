import ImageIO
import Kingfisher
import UIKit

extension UIImage {
    /// 是否为需要 AnimatedImageView 播放的多帧图片。
    ///
    /// 暴露 Canvas 层需要的图片形态事实，避免 Features 直接引用 Kingfisher。
    var isReaderAnimatedImage: Bool {
        (kf.imageFrameCount ?? 1) > 1
    }
}

/// 描述 Reader 当前需要的静态图内存显示尺寸：按屏幕物理像素封顶的宽度。
nonisolated struct ReaderPageImageDisplayMode: Equatable, Sendable {
    /// 显示位图允许的最大物理像素宽度。
    let maximumPixelWidth: Int

    /// 返回短期内存项使用的变体标识；不进入正式磁盘 Key。
    var memoryCacheVariant: String {
        "optimized-\(maximumPixelWidth)"
    }

    /// 返回脱敏的 Debug 模式描述。
    var logDescription: String {
        "optimized(\(maximumPixelWidth))"
    }
}

/// 同时保存正式磁盘缓存所需图片和当前内存显示位图。
nonisolated struct ReaderPagePreparedImage: Sendable {
    let cacheImage: UIImage
    let displayImage: UIImage
}

/// 在非 MainActor 上处理 Reader 静态图采样和动画解码。
nonisolated enum ReaderPageImagePreparer {
    /// 准备正式缓存内容和当前显示位图。
    @concurrent
    static func prepare(
        _ payload: SourcePagePayload,
        displayMode: ReaderPageImageDisplayMode,
    ) async throws -> ReaderPagePreparedImage {
        switch payload {
        case let .decoded(image):
            // 只有真正解扰完成的位图走这里；GIF 和无需解扰的老图仍走 encoded。
            guard image.width > 0,
                  image.height > 0
            else {
                throw ComicSourceError.invalidResponse
            }

            let cacheImage = UIImage(cgImage: image)
            return ReaderPagePreparedImage(
                cacheImage: cacheImage,
                displayImage: prepareStaticImage(
                    cacheImage,
                    displayMode: displayMode,
                ),
            )

        case let .encoded(data):
            let displayImage = try prepareEncodedImage(
                data,
                displayMode: displayMode,
            )
            // DefaultCacheSerializer 优先使用 originalData 写入磁盘，
            // 因此这里无需为静态编码图另外保留原尺寸 UIImage。
            return ReaderPagePreparedImage(
                cacheImage: displayImage,
                displayImage: displayImage,
            )
        }
    }

    /// 解码动画原数据，或从静态编码数据直接生成显示位图。
    private static func prepareEncodedImage(
        _ data: Data,
        displayMode: ReaderPageImageDisplayMode,
    ) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary,
        ) else {
            throw ComicSourceError.invalidResponse
        }

        if CGImageSourceGetCount(source) > 1,
           let animatedImage = KingfisherWrapper<UIImage>.animatedImage(
               data: data,
               options: ImageCreatingOptions(
                   scale: 1,
                   preloadAll: false,
               ),
           ) {
            // 动画图交给 AnimatedImageView 逐帧按需解码；Kingfisher 对动画图的 `.kf.decoded`
            // 本身就是 no-op（直接返回 base），这里保持原图，避免被误读成“需要解码全部帧”。
            return animatedImage
        }

        if let image = downsampledStaticImage(
            source: source,
            maximumPixelWidth: displayMode.maximumPixelWidth,
        ) {
            return image
        }

        guard let image = UIImage(data: data, scale: 1),
              image.size.width > 0,
              image.size.height > 0
        else {
            throw ComicSourceError.invalidResponse
        }

        return image.kf.decoded
    }

    /// 对来源已经还原的位图生成当前屏幕需要的静态显示副本。
    private static func prepareStaticImage(
        _ image: UIImage,
        displayMode: ReaderPageImageDisplayMode,
    ) -> UIImage {
        let maximumPixelWidth = displayMode.maximumPixelWidth
        guard let cgImage = image.cgImage,
              cgImage.width > maximumPixelWidth
        else {
            return image
        }

        let scale = CGFloat(maximumPixelWidth) / CGFloat(cgImage.width)
        let targetSize = CGSize(
            width: CGFloat(maximumPixelWidth),
            height: max((CGFloat(cgImage.height) * scale).rounded(), 1),
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: targetSize,
            format: format,
        ).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// 使用 ImageIO 直接从编码数据生成目标宽度位图，避免先完整解码大图。
    private static func downsampledStaticImage(
        source: CGImageSource,
        maximumPixelWidth: Int,
    ) -> UIImage? {
        guard maximumPixelWidth > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil,
              ) as? [CFString: Any],
              let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              rawWidth > 0,
              rawHeight > 0
        else {
            return nil
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsDimensions = 5 ... 8 ~= orientation
        let pixelWidth = swapsDimensions ? rawHeight : rawWidth
        let pixelHeight = swapsDimensions ? rawWidth : rawHeight
        guard pixelWidth > maximumPixelWidth else {
            return nil
        }

        let scale = CGFloat(maximumPixelWidth) / CGFloat(pixelWidth)
        let maximumDimension = Int(
            ceil(max(
                CGFloat(maximumPixelWidth),
                CGFloat(pixelHeight) * scale,
            )),
        )
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary,
        ) else {
            return nil
        }

        return UIImage(cgImage: image)
    }
}
