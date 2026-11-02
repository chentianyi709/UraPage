import Foundation

/// 描述用户通过几次点击显示或隐藏 Reader 控件。
enum ReaderChromeToggleMode: String, CaseIterable, Identifiable {
    case singleTap
    case doubleTap

    var id: String {
        rawValue
    }

    /// 返回设置页面展示的点击方式。
    var title: String {
        switch self {
        case .singleTap:
            "单击"
        case .doubleTap:
            "双击"
        }
    }

    /// 返回 UIKit 点击手势需要的连续点击次数。
    var tapCount: Int {
        switch self {
        case .singleTap:
            1
        case .doubleTap:
            2
        }
    }
}
