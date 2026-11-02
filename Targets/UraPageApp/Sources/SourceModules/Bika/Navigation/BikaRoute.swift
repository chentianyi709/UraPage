/// 哔咔的 push 目标。
///
/// 详情携带漫画身份与在线／离线模式；Reader 携带打开时确定的章节快照，不携带 Services。
/// 所属来源由类型自己声明（`SourceRouteValue`），App 层不做来源判断。
nonisolated enum BikaRoute: SourceDetailRoute {
    /// 漫画详情。
    case detail(ComicDetailRoute)

    /// 当前详情构造的在线阅读入口。
    case reader(ComicReaderInput)

    /// 指定上传者的作品列表；`name` 只用于页面标题展示。
    case uploaderComics(id: String, name: String)

    /// 详情作者行的作者、汉化组或上传者作品。
    case contributorComics(BikaComicContributor)

    /// 详情标签的作品列表。
    case tagComics(String)

    /// 详情分类的作品列表。
    case categoryComics(BikaComicCategory)

    var sourceID: ComicSourceID {
        .bika
    }

    /// 离线详情与离线 Reader 只读已下载资产，公共门禁据此免登录。
    ///
    /// 其余页面按在线处理：新增 route 自动继承「需要登录」，不需要逐个声明。
    var usesLocalAssetsOnly: Bool {
        switch self {
        case let .detail(route): route.mode == .offline
        case let .reader(input): input.contentMode == .offline
        default: false
        }
    }
}
