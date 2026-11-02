import Kingfisher
import SwiftUI
import UIKit

/// 显示 Canvas 中一张漫画页的图片、占位或单页失败状态。
final class ReaderCanvasPageView: UIView {
    // 静态页不创建动画播放器；GIF 只在真正进入视口时交给播放器并预载解码帧。
    // show(_:)／updateImagePresentation() 始终清空未使用一侧的 image，因此不会同时持有两份相同图片。
    private let staticImageView = UIImageView()
    private var animatedImageView: AnimatedImageView?
    private let pageLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    private var pageID: ReaderPagePosition?
    private var imageID: ObjectIdentifier?
    private var failure: ReaderPageFailure?
    private var isFailureRetryable = false
    private var retryAction: (() -> Void)?
    private var isVisibleInViewport = false
    /// 节点要求显示的图片；动画图是否交给播放器由视口与窗口状态决定。
    private var displayedImage: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 根据当前节点更新页码、图片和失败占位。
    ///
    /// 在线失败可点击重试；离线失败只读本地资产、重试无法恢复，因此显示终止原因且不响应点击。
    func configure(
        page: ReaderPageSlot,
        image: UIImage?,
        failure: ReaderPageFailure?,
        isRetryable: Bool,
        onRetry: @escaping () -> Void,
    ) {
        let nextImageID = image.map(ObjectIdentifier.init)
        let isSamePage = pageID == page.identity
        if isSamePage,
           imageID == nextImageID,
           self.failure == failure,
           isFailureRetryable == isRetryable {
            return
        }

        pageID = page.identity
        self.failure = failure
        isFailureRetryable = isRetryable
        retryAction = onRetry
        pageLabel.text = String(page.index + 1)

        if !isSamePage || imageID != nextImageID {
            show(image)
            imageID = nextImageID
        }

        pageLabel.isHidden = image != nil || failure != nil
        applyFailurePresentation(page: page)
        setNeedsLayout()
    }

    /// 失败占位：在线显示可点击的「加载失败」；离线显示终止原因且不可点击。
    private func applyFailurePresentation(page: ReaderPageSlot) {
        guard let failure else {
            retryButton.isHidden = true
            retryButton.isUserInteractionEnabled = false
            retryButton.accessibilityLabel = nil
            retryButton.accessibilityHint = nil
            return
        }

        retryButton.isHidden = false
        retryButton.isUserInteractionEnabled = isFailureRetryable
        if isFailureRetryable {
            retryButton.setTitle("加载失败", for: .normal)
            retryButton.accessibilityLabel = "第 \(page.index + 1) 页，加载失败"
            retryButton.accessibilityHint = failure.retryTitle
            retryButton.accessibilityTraits = .button
        } else {
            retryButton.setTitle(failure.localFailureTitle, for: .normal)
            retryButton.accessibilityLabel = "第 \(page.index + 1) 页，\(failure.localFailureTitle)"
            retryButton.accessibilityHint = nil
            retryButton.accessibilityTraits = .staticText
        }
    }

    /// 移除上一个节点的图片、文字和操作。
    func prepareForReuse() {
        pageID = nil
        imageID = nil
        failure = nil
        isFailureRetryable = false
        retryAction = nil
        displayedImage = nil
        staticImageView.image = nil
        staticImageView.isHidden = true
        isVisibleInViewport = false
        animatedImageView?.stopAnimating()
        animatedImageView?.image = nil
        animatedImageView?.isHidden = true
        pageLabel.text = nil
        retryButton.isHidden = true
        retryButton.isUserInteractionEnabled = false
        retryButton.accessibilityLabel = nil
        retryButton.accessibilityHint = nil
        retryButton.accessibilityTraits = .button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        staticImageView.frame = bounds
        animatedImageView?.frame = bounds
        pageLabel.frame = bounds

        guard !retryButton.isHidden else { return }

        // 控件宽度始终留在页面内；不能把长文案的自然宽度直接用于 frame，避免两端被裁掉。
        let buttonWidth = max(bounds.width - 48, 0)
        let buttonSize = retryButton.sizeThatFits(CGSize(width: buttonWidth, height: bounds.height))
        let buttonHeight = min(buttonSize.height, bounds.height)
        retryButton.frame = CGRect(
            x: (bounds.width - buttonWidth) / 2,
            y: (bounds.height - buttonHeight) / 2,
            width: buttonWidth,
            height: buttonHeight,
        )
    }

    /// 创建不参与 Canvas 布局的单页展示子视图。
    private func setupViews() {
        // 避免直接调用生成的 UIColor resource getter；该 getter 在模拟器上会触发运行时异常。
        backgroundColor = UIColor(.readerBackground)
        clipsToBounds = true

        staticImageView.contentMode = .scaleToFill
        staticImageView.isHidden = true

        let pageLabelFont = UIFont.systemFont(
            ofSize: ReaderPagePlaceholderStyle.fontSize,
            weight: .black,
        )
        pageLabel.font = pageLabelFont.fontDescriptor
            .withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: ReaderPagePlaceholderStyle.fontSize) }
            ?? pageLabelFont
        pageLabel.textAlignment = .center
        pageLabel.textColor = UIColor(.readerText).withAlphaComponent(
            ReaderPagePlaceholderStyle.textOpacity,
        )

        // 沿用初版 Reader 的大字失败占位；页码与具体原因保留给无障碍朗读。
        retryButton.setTitle("加载失败", for: .normal)
        retryButton.setTitleColor(
            UIColor(.readerText).withAlphaComponent(ReaderPagePlaceholderStyle.textOpacity),
            for: .normal,
        )
        retryButton.titleLabel?.font = .systemFont(ofSize: 64, weight: .black)
        retryButton.titleLabel?.textAlignment = .center
        retryButton.titleLabel?.adjustsFontSizeToFitWidth = true
        retryButton.titleLabel?.minimumScaleFactor = 0.5
        retryButton.isHidden = true
        retryButton.addAction(
            UIAction { [weak self] _ in
                self?.retryAction?()
            },
            for: .touchUpInside,
        )

        addSubview(pageLabel)
        addSubview(staticImageView)
        addSubview(retryButton)
    }

    /// 预加载窗口包含屏幕外的 View；只有真正进入视口的 GIF 才创建动画播放器并预载帧。
    func setVisibleInViewport(_ isVisible: Bool) {
        guard isVisibleInViewport != isVisible else { return }

        isVisibleInViewport = isVisible
        updateImagePresentation()
    }

    /// Canvas 用来判断此 View 当前是否已经展示了图片，避免因弱引用失效而误判为未加载。
    var hasLoadedImage: Bool {
        staticImageView.image != nil || animatedImageView?.image != nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateImagePresentation()
    }

    /// 按视口与窗口状态把当前图片同步到静态或动画容器。
    ///
    /// 动画图只在进入视口且已挂到窗口时交给 AnimatedImageView：赋值会创建 animator
    /// 并异步预载 0...`framePreloadCount` 帧；离屏时把播放器 image 置空触发
    /// Kingfisher `reset()`，同步释放 animator 与已解码帧，避免渲染窗口里的离屏 GIF
    /// 常驻多帧解码数据。重新进入视口时从首帧重新播放（已知副作用，换掉离屏帧常驻）。
    private func updateImagePresentation() {
        guard let image = displayedImage else {
            staticImageView.image = nil
            staticImageView.isHidden = true
            animatedImageView?.stopAnimating()
            animatedImageView?.image = nil
            animatedImageView?.isHidden = true
            return
        }

        let isAnimated = image.isReaderAnimatedImage
        if isAnimated, isVisibleInViewport, window != nil {
            // 当前只让动画容器持有图片，静态容器保持为空。
            staticImageView.image = nil
            staticImageView.isHidden = true
            let animatedImageView = makeAnimatedImageViewIfNeeded()
            if animatedImageView.image !== image {
                animatedImageView.image = image
            }
            animatedImageView.isHidden = false
            animatedImageView.startAnimating()
        } else {
            // 静态容器显示首帧；停止播放并把播放器 image 置空，释放 animator 及其已解码帧。
            animatedImageView?.stopAnimating()
            animatedImageView?.image = nil
            animatedImageView?.isHidden = true
            staticImageView.image = image
            staticImageView.isHidden = false
        }
    }

    private func makeAnimatedImageViewIfNeeded() -> AnimatedImageView {
        if let animatedImageView {
            return animatedImageView
        }
        let view = AnimatedImageView()
        view.contentMode = .scaleToFill
        // Kingfisher 的自动播放只检查 window／superview，不判断 Canvas 的裁切范围。
        view.autoPlayAnimatedImage = false
        view.framePreloadCount = 8
        // 解码帧不在图片内存池里：进后台停播并释放预载帧，回前台由 Kingfisher 自动重建并续播。
        view.purgeFramesOnBackground = true
        view.frame = bounds
        insertSubview(view, belowSubview: retryButton)
        animatedImageView = view
        return view
    }

    /// 记录节点当前应显示的图片，并按视口状态选择静态或动画容器。
    private func show(_ image: UIImage?) {
        displayedImage = image
        updateImagePresentation()
    }
}
