/// 一个来源自己的 push 目标值。
///
/// 由各来源的 `Route` 枚举实现：来源自己声明所属 `sourceID`，
/// 因此 App 层不需要穷尽判断来源，新增来源也不用改这个文件。
nonisolated protocol SourceRouteValue: Hashable, Sendable {
    /// 该路由所属来源；决定 destination 由哪个 Module 构建。
    var sourceID: ComicSourceID { get }
}

/// `AppRouter.path` 里的 push 目标：所有来源 typed route 的容器。
///
/// 只做类型擦除与身份暴露，不判断任何具体来源：`sourceID` 由路由值自己提供，
/// 具体 route 类型由对应来源 Module 按自己的 `Route` 解包（§7.1 允许的来源分派点）。
nonisolated struct AnySourceRoute: Hashable, Sendable {
    /// 具体来源的 route 值；协议已要求 `Hashable & Sendable`。
    private let value: any SourceRouteValue

    /// 目标来源。
    var sourceID: ComicSourceID {
        value.sourceID
    }

    /// 具体来源路由值；注册项按自己的 `Route` 类型解包。
    var routeValue: any SourceRouteValue {
        value
    }

    init(_ value: some SourceRouteValue) {
        self.value = value
    }

    /// 按具体 route 值判等：同类 route 比较其自身字段，不同来源必定不等。
    static func == (lhs: Self, rhs: Self) -> Bool {
        AnyHashable(lhs.value) == AnyHashable(rhs.value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(value))
    }
}

extension AnySourceRoute: CustomStringConvertible {
    /// 日志与断言里的可读描述；避免只看到擦除后的类型名。
    var description: String {
        "\(sourceID.rawValue):\(value)"
    }
}
