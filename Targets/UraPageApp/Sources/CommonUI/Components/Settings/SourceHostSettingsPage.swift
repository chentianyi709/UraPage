import SwiftUI

/// 来源设置页的公共外壳：服务器线路设置 + 来源自己的额外设置项。
///
/// 线路模型由本页持有并负责首次加载；来源只提供额外内容与 Services，
/// 不重复写 `SourceHostSettingsModel` 的闭包接线。额外内容排在前面，
/// 保持「来源设置在上、线路在下」的现有顺序。
struct SourceHostSettingsPage<Services: SourceHostSettingsProviding, ExtraContent: View>: View {
    @State private var hostModel: SourceHostSettingsModel?

    let services: Services
    @ContentBuilder let extraContent: (Services) -> ExtraContent

    init(
        services: Services,
        @ContentBuilder extraContent: @escaping (Services) -> ExtraContent,
    ) {
        self.services = services
        self.extraContent = extraContent
    }

    var body: some View {
        Form {
            extraContent(services)

            if let hostModel {
                SourceHostSettingsContent(model: hostModel)
            }
        }
        .task {
            guard hostModel == nil else {
                return
            }

            let model = SourceHostSettingsModel(services: services)
            hostModel = model
            model.loadIfNeeded()
        }
    }
}

extension SourceHostSettingsPage where ExtraContent == EmptyView {
    /// 只有服务器线路的漫画源设置页。
    init(services: Services) {
        self.init(services: services) { _ in
            EmptyView()
        }
    }
}
