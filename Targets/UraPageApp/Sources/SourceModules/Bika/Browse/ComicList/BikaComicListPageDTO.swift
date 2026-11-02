import ReerCodable

/// 解码哔咔通用漫画列表响应中的分页容器。
@Decodable
struct BikaComicListResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let comics: BikaComicListPageDTO
}

/// 保存分类与最近更新共用的作品、当前页和总页数。
@Decodable
struct BikaComicListPageDTO: Decodable, ReerCodableDelegate, Sendable {
    let docs: [BikaComicListItemDTO]

    /// 服务端返回的当前页；必须与请求页一致才接受。
    let page: Int

    /// 服务端总页数；`page < pages` 判断是否继续分页。
    let pages: Int
}
