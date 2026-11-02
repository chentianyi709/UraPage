import Foundation

/// 将禁漫普通列表 DTO 转换为跨页面复用的最小漫画卡片展示值。
///
/// 身份为空表示该条无法建立稳定身份：返回 `nil` 由调用方跳过该项，
/// 不抛错、也不影响同批其它条目（与响应级错误区分）。
/// 副标题使用作者，具体语义只在这里整理，公共层不理解。
/// 更新时间原样交给列表项：是否据此显示标记由本源页面决定（见 `JMComicUpdateTag`）。
func makeJMComicListItem(from comic: JMComicListItemDTO) -> ComicListItem? {
    guard !comic.id.isEmpty else {
        return nil
    }

    return ComicListItem(
        identity: ComicIdentity(sourceID: .jm, comicID: comic.id),
        title: comic.name,
        subtitle: comic.author,
        cover: .remote(
            makeJMCoverReference(
                comicID: comic.id,
                image: comic.image,
                updatedAt: comic.updatedAt,
            ),
        ),
        // 服务端缺省是 0（1970 年），按「没有更新时间」处理。
        updatedAt: comic.updatedAt > 0
            ? Date(timeIntervalSince1970: TimeInterval(comic.updatedAt))
            : nil,
    )
}
