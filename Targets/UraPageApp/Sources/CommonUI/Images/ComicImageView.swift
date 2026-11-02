import SwiftUI
import UIKit

extension EnvironmentValues {
    /// 浏览体验的普通图片工作域存储槽；写入用 `\.browsingImageScopeStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var browsingImageScopeStorage: BrowsingImageScope?

    /// 页面图片解析能力存储槽；写入用 `\.browsingImageServiceStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var browsingImageServiceStorage: (any ComicImageService)?

    /// 读取入口：由页面组合边界安装，未安装即暴露装配错误。
    var browsingImageScope: BrowsingImageScope {
        guard let browsingImageScopeStorage else {
            preconditionFailure("browsingImageScope 未安装：图片组件必须位于来源页面组合边界内")
        }

        return browsingImageScopeStorage
    }

    /// 读取入口：由页面组合边界安装（目标来源自己的实例），未安装即暴露装配错误。
    var browsingImageService: any ComicImageService {
        guard let browsingImageServiceStorage else {
            preconditionFailure("browsingImageService 未安装：图片组件必须位于来源页面组合边界内")
        }

        return browsingImageServiceStorage
    }
}

/// 普通远程图片的显示订阅组件。
///
/// 只负责：接收稳定引用与调用方给定的目标尺寸、从 Environment 读取 scope 与图片服务、
/// 展示 loading/success/failure、以及在引用或尺寸变化时解除旧订阅。
/// 它不查询缓存、不拼接 URL、不按来源分支；共享加载工作由 `BrowsingImageScope` 持有。
struct ComicImageView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.browsingImageScope) private var scope
    @Environment(\.browsingImageService) private var imageService

    let reference: ComicImageReference
    let targetSize: CGSize

    /// 是否按目标尺寸降采样；详情页大图与长按预览传 `false`。
    let downsamples: Bool

    @State private var image: UIImage?
    @State private var failed = false

    /// 来源图片环境变化后的重试令牌；只用于重新订阅尚未显示图片的请求。
    ///
    /// 与 `scope.requestGeneration` 分工：本令牌只决定当前组件是否重启 `.task`（已显示图片不重载）；
    /// scope 代次负责取消在途工作、隔离新旧任务，并在 `load()` 中丢弃旧环境的迟到结果。
    @State private var retryToken = 0

    init(
        reference: ComicImageReference,
        targetSize: CGSize,
        downsamples: Bool = true,
    ) {
        self.reference = reference
        self.targetSize = targetSize
        self.downsamples = downsamples
    }

    var body: some View {
        ZStack {
            ComicCoverPlaceholder(size: targetSize, failed: failed)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: targetSize.width, height: targetSize.height, alignment: .center)
                    .clipped()
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .clipped()
        .task(id: loadIdentity) {
            await load()
        }
        // 来源图片环境切换取消了在途请求；只重试尚未显示图片的组件，已显示的图片保持不动。
        .onChange(of: scope.requestGeneration) {
            guard image == nil else {
                return
            }

            retryToken += 1
        }
    }

    /// 引用、目标尺寸、屏幕 scale、是否降采样与重试令牌共同决定一次显示订阅身份。
    private struct LoadIdentity: Hashable {
        let reference: ComicImageReference
        let width: CGFloat
        let height: CGFloat
        let scale: CGFloat
        let downsamples: Bool
        let retryToken: Int
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(
            reference: reference,
            width: targetSize.width,
            height: targetSize.height,
            scale: max(displayScale, 1),
            downsamples: downsamples,
            retryToken: retryToken,
        )
    }

    /// 订阅当前显示身份；本组件不取消 scope 中共享的加载工作。
    private func load() async {
        // 记录发起时的环境代次；旧请求即使晚到，也不能把旧环境结果显示到新环境上。
        let generation = scope.requestGeneration
        image = nil
        failed = false

        do {
            let loaded = try await scope.image(
                for: reference,
                targetSize: targetSize,
                displayScale: max(displayScale, 1),
                downsamples: downsamples,
                using: imageService,
            )
            try Task.checkCancellation()
            guard generation == scope.requestGeneration else {
                return
            }

            image = loaded
        } catch is CancellationError {
            return
        } catch {
            guard generation == scope.requestGeneration else {
                return
            }

            failed = true
            AppLogger.error(
                "图片加载失败，source=\(reference.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Image",
            )
        }
    }
}
