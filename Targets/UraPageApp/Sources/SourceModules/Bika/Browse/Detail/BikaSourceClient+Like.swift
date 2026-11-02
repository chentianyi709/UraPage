import Alamofire

extension BikaSourceClient {
    /// 切换指定哔咔作品的点赞状态，并返回服务端确认的最终状态。
    ///
    /// 走写操作入口：POST 不自动重放，避免网络恢复把一次切换执行两次。
    func toggleComicLike(
        comicID: String,
    ) async throws -> BikaComicLikeState {
        AppLogger.debug(
            "开始切换漫画点赞，id=\(comicID)",
            category: "Bika.Like",
        )

        let response = try await write { state in
            try await state.session
                .request(
                    "comics/\(comicID)/like",
                    method: .post,
                )
                .bikaDecodedResponse(as: BikaComicLikeActionDTO.self)
        }
        let result: BikaComicLikeState = switch response.action {
        case .like:
            .liked

        case .unlike:
            .notLiked
        }

        AppLogger.info(
            "漫画点赞切换完成，id=\(comicID)，isLiked=\(result == .liked)",
            category: "Bika.Like",
        )
        return result
    }
}
