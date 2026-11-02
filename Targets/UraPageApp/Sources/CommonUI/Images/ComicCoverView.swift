import ImageIO
import SwiftUI
import UIKit

/// 按展示值选择在线图片管线或下载资产；本地封面始终只读本地文件。
struct ComicCoverView: View {
    let source: ComicImageSource
    let targetSize: CGSize

    /// 是否按目标尺寸降采样；详情页大图与长按预览传 `false`，直接显示原图以保证清晰度。
    var downsamples = true

    var body: some View {
        switch source {
        case let .remote(reference):
            ComicImageView(
                reference: reference,
                targetSize: targetSize,
                downsamples: downsamples,
            )

        case let .downloaded(reference: reference):
            if let reference {
                DownloadedComicCoverView(
                    reference: reference,
                    targetSize: targetSize,
                    downsamples: downsamples,
                )
            } else {
                ComicCoverPlaceholder(size: targetSize)
                    .frame(width: targetSize.width, height: targetSize.height)
            }
        }
    }
}

/// 封面占位：底色块＋居中图标；图标按容器短边缩放并限制显示范围，三个封面组件共用。
struct ComicCoverPlaceholder: View {
    let size: CGSize

    /// 加载失败时展示带提示的图标；未加载时是普通占位。
    var failed = false

    var body: some View {
        Rectangle()
            .fill(Color.divider)
            .overlay {
                Image(systemName: failed ? "photo.badge.exclamationmark" : "photo")
                    .font(.system(size: iconSize))
                    .foregroundStyle(Color.iconSecondary)
            }
    }

    private var iconSize: CGFloat {
        min(max(min(size.width, size.height) * 0.2, 12), 48)
    }
}

/// 从下载资产读取本地封面并按当前尺寸降采样；解码结果复用 App 全局共享内存池，不访问来源或在线缓存。
private struct DownloadedComicCoverView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.downloadAssetStore) private var assetStore
    @Environment(\.imageMemoryPool) private var imageMemoryPool

    let reference: ComicImageReference
    let targetSize: CGSize

    /// 是否按目标尺寸降采样；详情页大图与长按预览传 `false`，直接显示原图。
    var downsamples = true

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            ComicCoverPlaceholder(size: targetSize, failed: failed)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: targetSize.width, height: targetSize.height)
                    .clipped()
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .clipped()
        .task(id: loadIdentity) {
            await load()
        }
    }

    private struct LoadIdentity: Hashable {
        let reference: ComicImageReference
        let width: CGFloat
        let height: CGFloat
        let scale: CGFloat
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(
            reference: reference,
            width: targetSize.width,
            height: targetSize.height,
            scale: max(displayScale, 1),
        )
    }

    private func load() async {
        image = nil
        failed = false

        let cacheKey = memoryCacheKey
        if let cachedImage = imageMemoryPool.image(forKey: cacheKey) {
            image = cachedImage
            return
        }

        do {
            let data = try await assetStore.readCover(for: reference)
            let loadedImage = try await Self.preparedCover(
                data,
                targetSize: targetSize,
                displayScale: displayScale,
                downsamples: downsamples,
            )
            try Task.checkCancellation()
            // 与在线图片共用同一份固定上限内存池；命中即省掉读盘与解码。
            imageMemoryPool.store(loadedImage, forKey: cacheKey)
            image = loadedImage
        } catch is CancellationError {
            return
        } catch {
            failed = true
            AppLogger.error(
                "本地封面读取失败，source=\(reference.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Image",
            )
        }
    }

    /// 本地封面的内存池 key：与来源图片 key（`image.v1.*`）区分，身份沿用封面资产的稳定摘要。
    /// 不降采样时用 `original` 变体，与各降采样结果分开存放。
    ///
    /// 额外带上请求 locator：资产文件名可能保持不变（例如来源在 `assetIdentity` 中剔除了
    /// 临时版本参数），但引用变化意味着可能已重新下载了新字节，内存 key 需要跟着变化，
    /// 才能读到新文件而不是旧解码图。
    private var memoryCacheKey: String {
        let variant = downsamples
            ? "\(Self.maximumPixelSize(for: targetSize, displayScale: displayScale))"
            : "original"
        return "downloaded-cover.v1.\(variant).\(DownloadAssetPaths.coverRelativePath(for: reference)).\(reference.locator)"
    }

    /// 目标显示尺寸对应的最长边像素；同一尺寸复用同一份内存池结果。
    private static func maximumPixelSize(for targetSize: CGSize, displayScale: CGFloat) -> Int {
        Int((max(targetSize.width, targetSize.height) * max(displayScale, 1)).rounded(.up))
    }

    /// 在通用执行器上准备本地封面位图；`downsamples` 为假时按原图解码，保证详情大图与长按预览清晰度。
    @concurrent
    private static func preparedCover(
        _ data: Data,
        targetSize: CGSize,
        displayScale: CGFloat,
        downsamples: Bool,
    ) async throws -> UIImage {
        guard downsamples else {
            guard let image = UIImage(data: data),
                  let decoded = image.preparingForDisplay()
            else {
                throw DownloadAssetError.corruptedAsset
            }

            return decoded
        }

        let cgImage = try await downsampledCover(
            data,
            maximumPixelSize: maximumPixelSize(for: targetSize, displayScale: displayScale),
        )
        return UIImage(cgImage: cgImage)
    }

    /// 按目标尺寸降采样本地封面，避免阻塞主线程。
    @concurrent
    private static func downsampledCover(_ data: Data, maximumPixelSize: Int) async throws -> CGImage {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maximumPixelSize, 1),
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else {
            throw DownloadAssetError.corruptedAsset
        }

        return thumbnail
    }
}
