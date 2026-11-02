/// 校验哔咔服务端分页边界，并把有效卡片转换为公开结果页。
///
/// 服务端返回页与请求页不一致时说明分页已错位，直接抛错；
/// 单张卡片缺少有效 identity 或封面 locator 时只跳过该项。
/// 去重不在这里做：页内/跨页重复交由公共分页模型统一处理。
func makeBikaComicPage(
    from response: BikaComicListPageDTO,
    expectedPage: Int,
) throws -> BikaComicPage {
    guard response.page == expectedPage else {
        throw BikaAPIError.invalidResponse
    }

    return BikaComicPage(
        items: SourceItemMapping.compactMap(response.docs, category: "Bika.ComicList") { comic in
            makeBikaComicListItem(from: comic)
        },
        page: response.page,
        totalPages: response.pages,
    )
}
