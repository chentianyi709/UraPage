/// 描述禁漫分类菜单中的一个节点及其有序子分类。
struct JMComicCategory: Identifiable, Sendable {
    var id: String {
        slug
    }

    let name: String
    let slug: String
    let children: [JMComicCategory]

    /// 创建已脱离 DTO 的分类节点。
    init(name: String, slug: String, children: [JMComicCategory]) {
        self.name = name
        self.slug = slug
        self.children = children
    }
}

/// 使用从根节点到当前节点的完整 slug path 标识禁漫分类选择。
struct JMComicCategorySelection: Hashable, Sendable {
    let path: [String]

    /// 创建分类选择；全部为空的 path 归一为服务端默认分类。
    init(path: [String]) {
        self.path = path.allSatisfy(\.isEmpty) ? [] : path
    }

    /// 返回 `/categories/filter` 使用的分类参数（各级 slug 用 `_` 连接）。
    var requestSlug: String {
        path.joined(separator: "_")
    }
}
