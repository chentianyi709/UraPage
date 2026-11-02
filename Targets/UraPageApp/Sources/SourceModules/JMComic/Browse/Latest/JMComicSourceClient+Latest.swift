import Alamofire

extension JMComicSourceClient {
    /// 请求禁漫指定页的最新漫画，并给出下一页规则。
    ///
    /// 末页判断使用**原始响应条数**（不是跳过坏卡片后的数量），否则一页中出现坏卡片
    /// 会被误判成最后一页（§10.4）；页内与跨页重复仍由公共分页模型统一去重。
    func latest(page: Int) async throws -> ComicPageSlice<Int> {
        let comics = try await read { state in
            try await state.session
                .request(
                    "/latest",
                    method: .get,
                    parameters: ["page": page],
                    encoding: URLEncoding.default,
                )
                .jmComicDecodedResponse(as: [JMComicListItemDTO].self)
        }

        // 单个坏卡片只跳过自身，继续提交本页其它漫画。
        let items = SourceItemMapping
            .compactMap(comics, category: "JM.Latest") { makeJMComicListItem(from: $0) }
        let continuation: ComicPageContinuation<Int> = .whileMakingProgress(
            cursor: page + 1,
            hasMore: comics.count == JMComicConfiguration.Browse.latestPageSize,
        )

        return ComicPageSlice(items: items, continuation: continuation)
    }
}
