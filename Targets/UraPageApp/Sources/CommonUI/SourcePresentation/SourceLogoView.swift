import SwiftUI

/// 来源 Logo 的统一展示组件。
///
/// 三个来源的 Logo 画法不同：禁漫是透明底 PNG（需要白色底衬）、哔咔是完整方图、绅士没有资源，
/// 用品牌色圆角矩形衬一个汉字自绘。这里把它们统一成同一尺寸与圆角规格，供来源切换弹窗、
/// 来源设置、书架等处复用，调用方不再判断来源。
///
/// Logo 由调用方显式给出，组件不读来源环境：保证来源环境之外的 App 级弹窗
/// （如来源切换）也能渲染任意来源的 Logo。
///
/// 规格：边长由调用方给出，圆角固定为边长的 `cornerRadiusRatio`（连续圆角），
/// 因此任何尺寸下的轮廓都一致。
///
/// 说明：系统 `Menu` 的 label 只接受真正的 `Image`，不能直接放本视图；将来若要在菜单里
/// 使用这些 Logo，需要用 `ImageRenderer` 把绘制结果渲染成 `UIImage` 并缓存。
struct SourceLogoView: View {
    /// 轮廓形状；列表与来源切换处用圆角方形，详情页工具栏等位置用圆形。
    enum Outline: Sendable {
        case roundedRectangle
        case circle
    }

    /// 圆角占边长的比例；调大调小都会同时作用于三个来源。
    private static let cornerRadiusRatio: CGFloat = 0.22

    /// 要展示的 Logo。
    private let logo: SourceLogo

    /// 展示边长。
    let size: CGFloat

    /// 轮廓形状。
    private let outline: Outline

    /// 展示指定来源的 Logo。
    init(_ logo: SourceLogo, size: CGFloat = 32, outline: Outline = .roundedRectangle) {
        self.logo = logo
        self.size = size
        self.outline = outline
    }

    var body: some View {
        artwork
            .frame(width: size, height: size)
            .clipShape(outlineShape)
            .accessibilityHidden(true)
    }

    /// 按轮廓裁剪；圆形用于详情页工具栏。
    private var outlineShape: AnyShape {
        switch outline {
        case .roundedRectangle:
            AnyShape(RoundedRectangle(cornerRadius: size * Self.cornerRadiusRatio, style: .continuous))

        case .circle:
            AnyShape(Circle())
        }
    }

    /// 按来源的 Logo 类型绘制内容。
    @ContentBuilder
    private var artwork: some View {
        switch logo {
        case let .asset(name):
            // 透明底图片先垫白色，保证三个来源在任意背景上的轮廓一致。
            ZStack {
                Color.white

                Image(name)
                    .resizable()
                    .scaledToFill()
            }

        case let .drawn(monogram):
            ZStack {
                outlineShape
                    .fill(Color.brandPrimary.gradient)

                Text(monogram)
                    .font(.system(size: size * 0.56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}
