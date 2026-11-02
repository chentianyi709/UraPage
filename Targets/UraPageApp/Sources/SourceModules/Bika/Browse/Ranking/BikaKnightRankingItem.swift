/// 保存哔咔骑士榜一名用户的页面展示内容。
struct BikaKnightRankingItem: Identifiable, Hashable, Sendable {
    let accountID: String
    let displayName: String
    let avatar: ComicImageReference?
    let uploadedComicCount: Int
    let level: Int
    let title: String
    let slogan: String

    /// 使用稳定服务端账号 ID 作为列表 identity。
    var id: String {
        accountID
    }

    /// 创建一项已经由哔咔 Source Target 整理完成的骑士榜展示值。
    init(
        accountID: String,
        displayName: String,
        avatar: ComicImageReference?,
        uploadedComicCount: Int,
        level: Int,
        title: String,
        slogan: String,
    ) {
        self.accountID = accountID
        self.displayName = displayName
        self.avatar = avatar
        self.uploadedComicCount = uploadedComicCount
        self.level = level
        self.title = title
        self.slogan = slogan
    }
}
