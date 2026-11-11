import Foundation

/// 一种检索维度：分类、标签、作者、角色……
///
/// `id` 是持久化与路由身份（书签按它落库、来源按它分发），`title` 与 `systemImage` 只影响展示。
/// 同一来源的同一维度必须复用同一个值：标准维度直接用这里的三份预置值，
/// 来源自有的维度在来源模块里定义常量，详情分组、书签目录与路由判断三处共用，
/// 避免 id 与展示在两处各写一份后悄悄漂移。
struct ComicTagKind: Hashable, Codable, Sendable, Identifiable {
    /// 稳定标识，发布后不可修改。
    let id: String

    /// 分区标题与无障碍文案使用的名称。
    let title: String

    /// 分区标题与书签胶囊左侧的 SF Symbol。
    let systemImage: String

    /// 作者；详情里的作者是独立的内联行，这个维度供「作者列表页」的收藏使用。
    static let author = ComicTagKind(id: "author", title: "作者", systemImage: "person")

    /// 分类。
    static let category = ComicTagKind(id: "category", title: "分类", systemImage: "square.grid.2x2")

    /// 标签。
    static let tag = ComicTagKind(id: "tag", title: "标签", systemImage: "tag.fill")

    /// 来源目录里查不到该维度时的展示值：标题退回标识本身，图标用通用标签。
    static func unknown(_ id: String) -> ComicTagKind {
        ComicTagKind(id: id, title: id, systemImage: "tag")
    }

    /// 身份只取 `id`：`title` 与 `systemImage` 是展示信息。
    ///
    /// 分组去重、来源路由分发与下载检索列都按维度比较；若判等包含展示字段，
    /// 来源替换文案或图标后会出现「同 id 却匹配不上」的静默失配。
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// 详情页的一组标签：同一维度的若干展示值，组序即展示顺序。
///
/// 一个来源的同一维度只应出现一组——`id` 取维度标识，重复分组会撞 `ForEach` 的身份。
/// 组内值只是展示名：点击时由来源按名字回查本源数据。有些维度只做展示，必须照常渲染；
/// 公共层不判断可点性、所有组都渲染成胶囊，来源在 `onSelectTag` 里不处理该维度时，
/// 点击无动作是允许的（当前不做可点性标记，需要视觉或无障碍区分时再增加展示态入口）。
/// 这些值随详情快照进入离线 extras；作品行的检索列只取 `.tag` 与 `.category` 两组，
/// 其他维度不参与下载检索。
struct ComicTagGroup: Hashable, Codable, Sendable, Identifiable {
    let kind: ComicTagKind

    /// 组内值，保持来源给的顺序；空串由展示层过滤。
    let values: [String]

    var id: String {
        kind.id
    }
}
