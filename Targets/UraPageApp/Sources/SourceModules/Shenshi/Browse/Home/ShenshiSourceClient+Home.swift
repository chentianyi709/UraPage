import Alamofire

extension ShenshiSourceClient {
    /// 请求绅士移动端首页，并转换为推荐页纵向分区。
    func homeSections() async throws -> [ShenshiHomeSection] {
        try await read { state in
            try await state.session
                .request("/")
                .shenshiParsedTextResponse { html in
                    try ShenshiHomeHTMLParser.sections(from: html)
                }
        }
    }
}
