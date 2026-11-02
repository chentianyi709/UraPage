import SwiftUI
import UIKit

/// 描述 Canvas 章节边界占位项需要显示的来源无关状态。
enum ReaderCanvasChapterBoundaryPresentation: Equatable {
    case loading(String)
    case failed(String)
}

/// 在漫画内容顶部或底部显示固定高度的章节加载与重试状态。
final class ReaderCanvasChapterBoundaryView: UIView {
    /// 决定边界内容靠近漫画内容的一侧显示，而不是被放在容器中央。
    enum Edge {
        case top
        case bottom
    }

    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let contentStack = UIStackView()
    private let edge: Edge

    private var presentation: ReaderCanvasChapterBoundaryPresentation?
    private var retryAction: (() -> Void)?

    /// 创建位于漫画内容顶部或底部的章节边界占位项。
    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 原地切换加载和失败状态；两种状态始终使用相同容器高度。
    func configure(
        presentation: ReaderCanvasChapterBoundaryPresentation?,
        onRetry: (() -> Void)?,
    ) {
        retryAction = onRetry
        guard self.presentation != presentation else {
            return
        }

        self.presentation = presentation
        switch presentation {
        case let .loading(message):
            messageLabel.text = message
            activityIndicator.isHidden = false
            messageLabel.isHidden = false
            retryButton.isHidden = true
            activityIndicator.startAnimating()

        case let .failed(message):
            var configuration = retryButton.configuration
            configuration?.title = message
            retryButton.configuration = configuration
            messageLabel.isHidden = true
            retryButton.isHidden = false
            activityIndicator.stopAnimating()

        case nil:
            messageLabel.text = nil
            messageLabel.isHidden = true
            retryButton.isHidden = true
            activityIndicator.stopAnimating()
        }
    }

    /// 创建不使用模糊材质、不会增加 Reader 滚动合成负担的边界内容。
    private func setupViews() {
        backgroundColor = UIColor(.readerBackground)

        messageLabel.font = .preferredFont(forTextStyle: .body).bold()
        messageLabel.textColor = UIColor(.readerText)
        messageLabel.textAlignment = .center
        messageLabel.lineBreakMode = .byTruncatingTail
        activityIndicator.color = UIColor(Color.accentColor)
        activityIndicator.isHidden = true

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "arrow.clockwise")
        configuration.imagePadding = 6
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .preferredFont(forTextStyle: .body).bold()
            return attributes
        }
        retryButton.configuration = configuration
        retryButton.tintColor = UIColor(.readerText)
        retryButton.isHidden = true
        messageLabel.isHidden = true
        retryButton.addAction(
            UIAction { [weak self] _ in
                self?.retryAction?()
            },
            for: .touchUpInside,
        )

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(activityIndicator)
        contentStack.addArrangedSubview(messageLabel)
        contentStack.addArrangedSubview(retryButton)
        addSubview(contentStack)

        var constraints = [
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ]
        switch edge {
        case .top:
            constraints.append(
                contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
            )

        case .bottom:
            constraints.append(
                contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            )
        }
        NSLayoutConstraint.activate(constraints)
    }
}

private extension UIFont {
    /// 在保留动态字体字号的同时应用粗体字重。
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else {
            return self
        }

        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
