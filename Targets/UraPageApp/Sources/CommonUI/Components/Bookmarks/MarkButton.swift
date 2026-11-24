import SwiftUI

/// 收藏／关注按钮的共用外观与状态机：读一次当前状态、点击立即切换、失败回滚。
///
/// 只负责图标、状态、读屏与触觉；`read`／`write` 由具体按钮注入——
/// 分类／标签走 `BookmarkStore`，作者走 `FollowingStore`，两套读写互不影响。
/// 按钮不固定 44×44 命中区：导航栏内容高度不足 44，固定方框会被压成椭圆底；
/// 交给系统按图标包一圈玻璃，和返回按钮一样是正的圆。
struct MarkButton: View {
    /// 读屏、失败提示与日志归类的文案。
    struct Labels {
        /// 读屏里的对象描述，如「分类：同人」「作者：xxx」。
        let subject: String
        /// 未选中时点击会做什么（「收藏」「关注」）。
        let onTitle: String
        /// 已选中时点击会做什么（「取消收藏」「删除」）。
        let offTitle: String
        /// 落盘失败时的提示，按目标状态区分。
        let failureMessage: (Bool) -> String
        /// 日志归类：书签与关注分开，排查时能看出是哪一边。
        let logCategory: String
    }

    /// 状态读取的任务标识；对象变化时先回到未知态再重读。
    let identity: String
    let labels: Labels
    let read: () async throws -> Bool
    let write: (Bool) async throws -> Void

    @State private var isOn: Bool?

    /// 触觉反馈计数：只在用户点击时自增，读取状态不会触发。
    @State private var feedbackCount = 0

    var body: some View {
        Button {
            toggle()
        } label: {
            Image(systemName: isOn == true ? "heart.fill" : "heart")
                .foregroundStyle(isOn == true ? Color.brandPrimary : Color.textPrimary)
        }
        .accessibilityLabel("\(isOn == true ? labels.offTitle : labels.onTitle)，\(labels.subject)")
        .accessibilityAddTraits(isOn == true ? .isSelected : [])
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackCount)
        .disabled(isOn == nil)
        .task(id: identity) {
            // 同一页面切换对象时先回到未知态，避免旧状态短暂套到新条目上。
            isOn = nil

            do {
                let saved = try await read()
                guard !Task.isCancelled else { return }

                isOn = saved
            } catch {
                guard !Task.isCancelled else { return }

                AppLogger.warning(
                    "标记状态读取失败，subject=\(labels.subject) errorType=\(type(of: error))",
                    category: labels.logCategory,
                )
                isOn = false
            }
        }
    }

    /// 点击即切换本地展示并落盘；失败回滚。
    ///
    /// 状态只在 `.task` 里读取一次，点击不再二次查询 store：
    /// 未读完前按钮禁用，读完后「看到什么就切换成相反」，不会出现点了取消却又收藏。
    private func toggle() {
        guard let current = isOn else { return }

        // 点击即给触觉反馈，不等落盘；读取状态的那点延迟不该让手感变钝。
        feedbackCount &+= 1

        let target = !current
        isOn = target

        Task {
            do {
                try await write(target)
            } catch {
                isOn = current
                AppLogger.warning(
                    "标记状态写入失败，subject=\(labels.subject) errorType=\(type(of: error))",
                    category: labels.logCategory,
                )
                ToastCenter.shared.show(labels.failureMessage(target), type: .error)
            }
        }
    }
}
