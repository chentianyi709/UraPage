import Observation
import SwiftUI

/// 详情页点赞交互的页面级状态 owner；与 `ComicDownloadController` 同构。
///
/// 只做三件事：拦住重复点击、提交来源给的点赞动作、把服务端确认的结果转成提示与展示态。
/// 当前展示的点赞值由页面把 `likedOverride` 与详情给出的值合成——详情重载后覆盖值仍要保留。
@MainActor
@Observable
final class ComicDetailLikeController {
    /// 服务端确认后的点赞态；`nil` 表示沿用详情给出的值。
    private(set) var likedOverride: Bool?

    /// 是否有请求在途；在途时底栏显示进度且不接受再次点击。
    private(set) var isLiking = false

    private let identity: ComicIdentity
    private let action: ComicDetailLikeAction

    init(identity: ComicIdentity, action: ComicDetailLikeAction) {
        self.identity = identity
        self.action = action
    }

    /// 提交一次点赞或取消点赞。
    ///
    /// - Parameter currentIsLiked: 当前展示的点赞态（已与覆盖值合成）。
    func toggle(currentIsLiked: Bool) {
        guard !isLiking else {
            return
        }

        // 不可取消点赞的来源在已点赞时只提示，不重复提交请求。
        guard action.allowsUnliking || !currentIsLiked else {
            ToastCenter.shared.show("已点赞", type: .info)
            return
        }

        isLiking = true
        let identity = identity
        let action = action

        Task { [weak self] in
            defer { self?.isLiking = false }

            do {
                let result = try await action.perform(identity)
                self?.apply(result)
            } catch is CancellationError {
                return
            } catch let error as ComicSourceError {
                ToastCenter.shared.show(
                    SourceLoadDisplayError(error).message,
                    type: .error,
                )
            } catch {
                ToastCenter.shared.show("点赞失败，请稍后重试", type: .error)
            }
        }
    }

    /// 只采用服务端确认后的状态，并在成功、取消成功与业务拒绝间区分提示类型。
    private func apply(_ result: ComicDetailLikeResult) {
        switch result {
        case let .liked(message):
            likedOverride = true
            ToastCenter.shared.show(message ?? "点赞成功", type: .success)

        case let .unliked(message):
            likedOverride = false
            ToastCenter.shared.show(message ?? "已取消点赞", type: .success)

        case let .rejected(message):
            ToastCenter.shared.show(message ?? "点赞失败", type: .warning)
        }
    }
}

/// 详情页点赞动作：来源声明是否支持取消点赞，并提交服务端确认的请求。
struct ComicDetailLikeAction: Sendable {
    /// 是否允许再次点击取消点赞。
    ///
    /// 为 `false` 时公共页面在已点赞状态下只提示「已点赞」，不发起请求；来源无需自行判断当前状态。
    let allowsUnliking: Bool

    /// 提交点赞或取消点赞；返回服务端确认后的结果。
    let perform: @Sendable (ComicIdentity) async throws -> ComicDetailLikeResult
}

/// 详情页点赞动作的服务端确认结果。
enum ComicDetailLikeResult: Sendable {
    /// 服务端确认已点赞；`message` 为空时使用默认成功提示。
    case liked(message: String?)

    /// 服务端确认已取消点赞（仅可切换点赞的来源）。
    case unliked(message: String?)

    /// 服务端拒绝，点赞状态保持不变。
    case rejected(message: String?)
}
