import Alamofire
import Foundation

extension JMComicSourceClient {
    /// 使用关键词、排序和页码搜索禁漫漫画。
    ///
    /// `searchType` 对应接口参数 `search_type`，默认值与源码搜索页一致为 `site`；
    /// `dateFilter` 对应可选参数 `y`／`m`，字段为空时不下发。
    /// 单张坏卡片只跳过自身；去重交公共分页模型。
    func searchComics(
        query: String,
        sort: JMComicSearchSort,
        searchType: JMComicSearchType = .site,
        dateFilter: JMComicSearchDateFilter? = nil,
        page: Int,
    ) async throws -> JMComicSearchComicPage {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw JMComicAPIError.invalidArgument
        }

        let response = try await read { state in
            // 参数在并发闭包内组装成 `[String: String]`（查询串编码结果不变，且可安全跨隔离）。
            var parameters = [
                "search_query": trimmedQuery,
                "o": sort.rawValue,
                "page": String(page),
                "search_type": searchType.rawValue,
            ]
            if let year = dateFilter?.requestYear {
                parameters["y"] = year
            }
            if let month = dateFilter?.requestMonth {
                parameters["m"] = month
            }

            return try await state.session
                .request(
                    "/search",
                    method: .get,
                    parameters: parameters,
                    encoding: URLEncoding.default,
                )
                .jmComicDecodedResponse(as: JMComicSearchResponseDTO.self)
        }

        // 单个坏卡片只跳过自身，不废弃整页搜索结果。
        let entries: [JMComicSearchComicPage.Entry] = SourceItemMapping.compactMap(
            response.content,
            category: "JM.Search",
        ) { dto in
            guard let comic = makeJMComicListItem(from: dto) else {
                return nil
            }

            return JMComicSearchComicPage.Entry(comic: comic, addedAt: dto.addedAt)
        }
        let redirectComicID = response.redirectComicID.trimmingCharacters(in: .whitespacesAndNewlines)

        return JMComicSearchComicPage(
            entries: entries,
            total: response.total,
            hasResponseItems: !response.content.isEmpty,
            redirectComicID: redirectComicID.isEmpty ? nil : redirectComicID,
        )
    }

    /// 读取搜索页热门搜索词；服务端 `data` 解密后就是字符串数组，不需要额外 DTO。
    ///
    /// 内容语言由公共拦截器统一追加（与其它 GET 一致），因此跟随用户的语言设置。
    /// **每次带一个唯一查询参数**：部分线路会按 URL 缓存 `/hot_tags` 的加密响应
    /// （缓存体只能用生成它时的时间戳解密，后续请求必然 `decryptionFailed`），
    /// 实测 `Cache-Control: no-cache` 无法绕过，只有让 URL 变化才会重新加密。
    func hotTags() async throws -> [String] {
        try await read { state in
            // 用随机值而不是时间戳：多个客户端同一秒内也不会命中彼此留下的缓存条目。
            let cacheBuster = UUID().uuidString

            return try await state.session
                .request("/hot_tags", method: .get, parameters: ["_": cacheBuster])
                .jmComicDecodedResponse(as: [String].self)
        }
    }
}
