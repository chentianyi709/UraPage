import SwiftUI

/// 来源图片环境切换后的公共失效能力；由 App Shell 实现，CommonUI 不反向引用 App 类型。
///
/// 来源设置页在成功切换“图片请求实际使用的环境”（例如禁漫的图片图源）后调用：
/// 取消当前来源体验仍在途的普通浏览图片请求，并让正在加载的图片立即重新发起请求。
/// 本能力不改变缓存身份、不清理已缓存或已显示的图片；公共层不解释来源的图片环境语义。
@MainActor
protocol SourceImageRequestInvalidationHandling: AnyObject {
    /// 取消指定来源当前激活体验的在途普通浏览图片请求；没有对应激活体验时不做任何事。
    func invalidateBrowsingImageRequests(for sourceID: ComicSourceID)
}

extension EnvironmentValues {
    /// 来源图片请求失效能力存储槽；写入用 `\.sourceImageRequestInvalidationStorage`。
    @Entry var sourceImageRequestInvalidationStorage: (any SourceImageRequestInvalidationHandling)?

    /// 读取入口：由 App Shell 在来源设置边界安装，未安装即暴露装配错误。
    var sourceImageRequestInvalidation: any SourceImageRequestInvalidationHandling {
        guard let storage = sourceImageRequestInvalidationStorage else {
            preconditionFailure("sourceImageRequestInvalidation 未安装：来源设置必须位于 App Shell 提供的弹窗边界内")
        }

        return storage
    }
}
