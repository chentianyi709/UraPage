/// 将哔咔骑士榜 DTO 转换为来源专属用户展示值。
///
/// 身份为空时该条不可用：返回 `nil` 由调用方跳过。
func makeBikaKnightRankingItem(from user: BikaKnightRankingUserDTO) -> BikaKnightRankingItem? {
    guard !user.id.isEmpty else {
        return nil
    }

    return BikaKnightRankingItem(
        accountID: user.id,
        displayName: user.name,
        // 头像不是榜单用户的 identity；坏头像降级为无头像，不丢弃整个用户条目。
        // 头像引用按约定传空 ownerID，由来源在同一头像的所有入口保持一致。
        avatar: user.avatar.flatMap {
            BikaImageReferenceFactory.make(
                ownerID: "",
                fileServer: $0.fileServer,
                path: $0.path,
                purpose: .avatar,
            )
        },
        uploadedComicCount: user.comicsUploaded,
        level: user.level,
        title: user.title,
        slogan: user.slogan,
    )
}
