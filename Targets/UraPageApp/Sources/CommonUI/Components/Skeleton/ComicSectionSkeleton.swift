import SwiftUI

/// 分区骨架容器：标题占位 + 内容槽，与真实 `ComicSection` 同一套标题行高与间距。
///
/// 内容自带水平内边距（`ComicCardSkeletonGridView`／`ComicCardSkeletonRowsView` 都自带），
/// 因此这里只处理标题行。
struct ComicSectionSkeleton<Content: View>: View {
    let showsDisclosureIndicator: Bool
    @ContentBuilder let content: () -> Content

    init(
        showsDisclosureIndicator: Bool = true,
        @ContentBuilder content: @escaping () -> Content,
    ) {
        self.showsDisclosureIndicator = showsDisclosureIndicator
        self.content = content
    }

    var body: some View {
        ComicSection {
            ComicSectionSkeletonHeader(showsDisclosureIndicator: showsDisclosureIndicator)
        } content: {
            content()
        }
    }
}
