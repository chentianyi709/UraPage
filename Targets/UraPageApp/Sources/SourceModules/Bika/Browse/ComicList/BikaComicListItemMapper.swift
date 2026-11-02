/// 将哔咔普通漫画 DTO 转换为跨来源漫画卡片展示值。
///
/// 身份为空或封面 locator 无效时该条不可用：返回 `nil` 由调用方跳过，
/// 不抛错、也不影响同批其它条目；作者为空时副标题为 `nil`，由展示层决定是否占位。
func makeBikaComicListItem(from comic: BikaComicListItemDTO) -> ComicListItem? {
    makeBikaComicListItem(id: comic.id, title: comic.title, author: comic.author, thumb: comic.thumb)
}

/// 个性化服务只给作品 ID；用已取得的详情响应构造同款卡片。
func makeBikaComicListItem(from comic: BikaComicDetailDTO) -> ComicListItem? {
    makeBikaComicListItem(id: comic.id, title: comic.title, author: comic.author, thumb: comic.thumb)
}

/// 列表与推荐补齐详情只在 DTO 的作者可选性上不同，卡片规则共用一处。
private func makeBikaComicListItem(
    id: String,
    title: String,
    author: String?,
    thumb: BikaImageDTO,
) -> ComicListItem? {
    guard !id.isEmpty,
          let cover = BikaImageReferenceFactory.make(
              ownerID: id,
              fileServer: thumb.fileServer,
              path: thumb.path,
              purpose: .cover,
          )
    else {
        return nil
    }

    return ComicListItem(
        identity: ComicIdentity(sourceID: .bika, comicID: id),
        title: title,
        subtitle: author?.isEmpty == false ? author : nil,
        cover: .remote(cover),
    )
}
