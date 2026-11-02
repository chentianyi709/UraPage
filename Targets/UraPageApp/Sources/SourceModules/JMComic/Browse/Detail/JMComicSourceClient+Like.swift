import Alamofire

extension JMComicSourceClient {
    /// 为指定禁漫作品提交一次不可撤销的点赞。
    ///
    /// 走写操作入口：POST 不自动重放；服务端业务失败由返回结果表达，不伪造点赞状态。
    func likeComic(comicID: String) async throws -> JMComicLikeResult {
        AppLogger.debug(
            "开始提交漫画点赞，id=\(comicID)",
            category: "JM.Like",
        )

        let response = try await write { state in
            try await state.session
                .request(
                    "/like",
                    method: .post,
                    parameters: [
                        "id": comicID,
                        "like_type": "",
                    ],
                    encoding: URLEncoding.httpBody,
                )
                .jmComicDecodedResponse(as: JMComicLikeResponseDTO.self)
        }

        let result = JMComicLikeResult(
            succeeded: response.status == "success",
            message: response.msg,
        )
        AppLogger.info(
            "漫画点赞返回，id=\(comicID)，succeeded=\(result.succeeded)",
            category: "JM.Like",
        )
        return result
    }
}
