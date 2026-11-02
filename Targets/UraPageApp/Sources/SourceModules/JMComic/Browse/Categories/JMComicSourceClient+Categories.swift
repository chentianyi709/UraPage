import Alamofire

extension JMComicSourceClient {
    /// 获取禁漫当前可用的递归分类树。
    func categories() async throws -> [JMComicCategory] {
        let response = try await read { state in
            try await state.session
                .request("/categories", method: .get)
                .jmComicDecodedResponse(as: JMComicCategoriesResponseDTO.self)
        }
        return response.categories.map(Self.makeCategory)
    }

    /// 递归移除 DTO 边界，保留服务端分类顺序和层级。
    private static func makeCategory(from dto: JMComicCategoryDTO) -> JMComicCategory {
        JMComicCategory(
            name: dto.name,
            slug: dto.slug,
            children: dto.subCategories.map(makeCategory),
        )
    }

    /// 按分类、排序和页码获取禁漫漫画列表。
    ///
    /// 分类参数是否转繁体由来源偏好决定；单张坏卡片只跳过自身，去重交公共分页模型。
    func categoryComics(
        category categorySlug: String,
        sort: JMComicSort,
        page: Int,
    ) async throws -> [ComicListItem] {
        let categoryParameter = sourcePreferences.usesTraditionalCategoryParameter()
            ? categorySlug.convertedToTraditionalChinese()
            : categorySlug

        let response = try await read { state in
            try await state.session
                .request(
                    "/categories/filter",
                    method: .get,
                    parameters: [
                        "page": page,
                        "c": categoryParameter,
                        "o": sort.rawValue,
                    ],
                    encoding: URLEncoding.default,
                )
                .jmComicDecodedResponse(as: JMComicCategoryFilterResponseDTO.self)
        }

        return SourceItemMapping
            .compactMap(response.content, category: "JM.Categories") { makeJMComicListItem(from: $0) }
    }
}
