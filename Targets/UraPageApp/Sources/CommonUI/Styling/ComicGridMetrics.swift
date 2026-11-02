import SwiftUI

/// 普通漫画网格、卡片与骨架屏共用的固定布局策略。
///
/// 与来源无关的展示常量集中在此，直接读取；调整后统一影响所有来源的网格。
/// 采用与旧版一致的固定三列布局，列宽由容器宽度算出。
enum ComicGridMetrics {
    /// 固定列数。
    static let columnCount = 3

    /// 同一行内相邻卡片的横向间距。
    static let gridSpacing: CGFloat = 8

    /// 网格水平外边距。
    static let horizontalPadding: CGFloat = 12

    /// 相邻两行之间的纵向间距。
    static let rowSpacing: CGFloat = 16

    /// 网格内容上下的留白。
    static let verticalPadding: CGFloat = 20

    /// 分区标题行高：可点标题的命中区与骨架占位同高，保证各分区标题到内容间距一致。
    static let sectionHeaderHeight: CGFloat = 44

    /// 分区标题与内容之间的间距。
    static let sectionSpacing: CGFloat = 12

    /// 两行横向卡片分区的固定卡片宽度（真实卡片与骨架共用）。
    static let shelfCardWidth: CGFloat = 120

    /// 封面圆角。
    static let coverCornerRadius: CGFloat = 8

    /// 用容器宽度计算与真实卡片一致的列宽。
    static func itemWidth(for containerWidth: CGFloat) -> CGFloat {
        itemWidth(forAvailableWidth: containerWidth - horizontalPadding * 2)
    }

    /// 父视图已经处理水平边距时，用实际可用宽度计算列宽。
    static func itemWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        let totalSpacing = gridSpacing * CGFloat(columnCount - 1)
        return max(availableWidth - totalSpacing, 0) / CGFloat(columnCount)
    }

    /// 创建真实网格与骨架屏共用的固定三列布局。
    static func columns(itemWidth: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(itemWidth), spacing: gridSpacing, alignment: .top),
            count: columnCount,
        )
    }

    /// 封面高度：漫画封面为竖向 3:4。
    static func coverHeight(forItemWidth itemWidth: CGFloat) -> CGFloat {
        itemWidth * 4 / 3
    }
}
