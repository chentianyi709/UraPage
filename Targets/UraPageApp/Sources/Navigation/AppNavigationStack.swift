import SwiftUI

/// 把来源路由解析成页面的窄接口；由 App 层的来源宿主实现并安装。
///
/// Navigation 只依赖页面解析能力，不需要知道 App Shell、来源注册表或组合根。
@MainActor
protocol SourceDestinationResolving {
    func destination(for route: AnySourceRoute) -> AnyView
}

extension EnvironmentValues {
    /// 来源页面解析器存储槽；写入用 `\.sourceDestinationResolverStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var sourceDestinationResolverStorage: (any SourceDestinationResolving)?

    /// 读取入口：由 App 安装，未安装即暴露装配错误。
    var sourceDestinationResolver: any SourceDestinationResolving {
        guard let sourceDestinationResolverStorage else {
            preconditionFailure("sourceDestinationResolver 未安装：导航容器必须位于来源体验根边界内")
        }

        return sourceDestinationResolverStorage
    }
}

/// 每个 Tab 共用的导航容器：绑定唯一 Router，并按目标来源构建 destination。
/// 来源只提供根内容；跨源页面仍留在发起方的导航栈内。
struct AppNavigationStack<Content: View>: View {
    @Environment(\.sourceDestinationResolver) private var destinationResolver

    let router: AppRouter
    @ContentBuilder let content: Content

    var body: some View {
        NavigationStack(path: router.pathBinding) {
            content
                .navigationDestination(for: AnySourceRoute.self) { route in
                    // 二级页面统一不显示 TabBar（返回栈内根页面时恢复）。
                    destination(for: route)
                        .toolbarVisibility(.hidden, for: .tabBar)
                }
        }
        .appNavigationBarScrollEdgeEffect()
    }

    private func destination(for route: AnySourceRoute) -> AnyView {
        destinationResolver.destination(for: route)
    }
}
