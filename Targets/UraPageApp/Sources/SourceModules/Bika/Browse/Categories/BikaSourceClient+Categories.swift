import Alamofire

extension BikaSourceClient {
    /// 获取哔咔当前可以在原生客户端展示的有序分类。
    ///
    /// 网页专属分类与空标题不能成为原生菜单项；只过滤坏项，不废弃其它分类。
    func categories() async throws -> [BikaComicCategory] {
        let response = try await read { state in
            try await state.session
                .request("categories", method: .get)
                .bikaDecodedResponse(as: BikaCategoriesResponseDTO.self)
        }

        return response.categories.compactMap { category in
            guard category.isWeb != true, !category.title.isEmpty else {
                return nil
            }

            return BikaComicCategory(title: category.title)
        }
    }
}
