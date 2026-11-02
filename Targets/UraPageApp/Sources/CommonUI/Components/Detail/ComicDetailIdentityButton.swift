import SwiftUI
import UIKit

/// 复制操作发生时生成的剪贴板内容与成功提示。
struct ComicDetailCopyResult: Sendable {
    let content: String
    let successMessage: String
}

/// 来源提供的异步复制内容生成操作；返回内容由详情页决定（例如分享文案）。
typealias ComicDetailCopyProvider = @Sendable () async throws -> ComicDetailCopyResult

/// 详情页作品 ID 按钮：展示 ID 并在点击时把来源生成的复制内容写入剪贴板。
struct ComicDetailIdentityButton: View {
    let comicID: String
    let copyContentProvider: ComicDetailCopyProvider

    @State private var copyTask: Task<Void, Never>?

    var body: some View {
        Button(action: startCopying) {
            HStack(spacing: 3) {
                Image(systemName: "number")
                Text(comicID)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(copyTask != nil)
        .accessibilityLabel("作品 ID \(comicID)")
        .accessibilityHint("双击复制")
        .onDisappear(perform: cancelCopying)
    }

    /// 单次复制任务：完成后写剪贴板并提示；离开页面时取消未完成的生成。
    private func startCopying() {
        guard copyTask == nil else {
            return
        }

        copyTask = Task {
            defer {
                copyTask = nil
            }

            do {
                let result = try await copyContentProvider()
                try Task.checkCancellation()
                UIPasteboard.general.string = result.content
                ToastCenter.shared.show(result.successMessage, type: .success)
            } catch is CancellationError {
                return
            } catch {
                ToastCenter.shared.show("复制失败，请稍后重试", type: .error)
            }
        }
    }

    private func cancelCopying() {
        copyTask?.cancel()
        copyTask = nil
    }
}
