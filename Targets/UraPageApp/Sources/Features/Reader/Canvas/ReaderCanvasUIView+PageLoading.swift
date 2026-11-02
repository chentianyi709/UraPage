import UIKit

extension ReaderCanvasUIView {
    /// 页面任务按章节位置共享；跳页、切章不改变其身份，也不取消已开始的工作。
    func loadPageIfNeeded(
        _ id: ReaderPagePosition,
        priority: ReaderPageLoadPriority,
    ) {
        guard let context = pageLoadContext(for: id, priority: priority) else {
            return
        }

        let pageAccess = context.pageAccess
        let imageDisplayMode = context.imageDisplayMode
        let slot = context.slot
        nextPageTaskID += 1
        let taskID = nextPageTaskID
        let pageImageLoader = pageImageLoader
        let task = Task(priority: priority.taskPriority) { [weak self] in
            do {
                // 未解析槽位与已解析页走同一任务：定位清单批次 → 取得真实身份 → 读缓存/下载。
                let batch: [ComicPage]
                if let resolved = slot.resolvedPage {
                    batch = [resolved]
                } else {
                    switch pageAccess {
                    case let .online(resolve, _):
                        batch = try await resolve(slot.identity)
                    case .downloadedAsset:
                        throw ReaderPageFailure.localAssetMissing
                    }
                }
                try Task.checkCancellation()
                guard let self, pageTasks[id]?.id == taskID else { return }

                applyResolvedPages(batch)
                // 旧章可能已不在展示节点中，仍须完成清单解析、图片下载和缓存。
                guard let page = batch.first(where: {
                    $0.identity.chapter == id.chapter && $0.index == id.index
                }) else {
                    // 来源 Mapper 跳过的坏单项，只令这一槽位失败，不压缩后面的序号。
                    throw ComicSourceError.invalidResponse
                }

                var preparedImage: UIImage?
                try await pageImageLoader.loadImage(
                    for: page,
                    displayMode: imageDisplayMode,
                    pageAccess: pageAccess,
                    onImagePrepared: { [weak self] image in
                        preparedImage = image
                        self?.presentPageImage(
                            id: id,
                            page: page,
                            image: image,
                            displayMode: imageDisplayMode,
                            taskID: taskID,
                        )
                    },
                )
                try Task.checkCancellation()
                // 图片可能在正式写盘期间重新进入窗口；再次提交同一对象是幂等的，
                // 可以补上第一次完成时仍处于范围外而没有挂载到节点的情况。
                if let preparedImage {
                    presentPageImage(
                        id: id,
                        page: page,
                        image: preparedImage,
                        displayMode: imageDisplayMode,
                        taskID: taskID,
                    )
                }
                finishPageLoad(
                    id: id,
                    taskID: taskID,
                )
            } catch is CancellationError {
                self?.finishPageCancellation(
                    id: id,
                    taskID: taskID,
                )
            } catch let failure as ReaderPageFailure {
                self?.finishPageFailure(
                    id: id,
                    failure: failure,
                    taskID: taskID,
                )
            } catch {
                self?.finishPageFailure(
                    id: id,
                    failure: ReaderPageFailure.map(error, fallback: .sourceUnavailable),
                    taskID: taskID,
                )
            }
        }
        pageTasks[id] = ReaderCanvasPageTask(
            id: taskID,
            task: task,
        )
    }

    /// 判断当前位置是否需要下发页面任务，并返回任务所需的输入。
    ///
    /// 条件按「环境就绪 → 节点有效 → 缺图或显示模式变化 → 未失败 → 在可加载范围 → 无在途任务」
    /// 分段判断，避免 `&&`／`||` 混排在同一个 guard 中；顺序与短路语义保持不变。
    private func pageLoadContext(
        for id: ReaderPagePosition,
        priority: ReaderPageLoadPriority,
    ) -> PageLoadContext? {
        guard let pageAccess,
              let imageDisplayMode,
              let index = nodeIndexByID[id],
              nodes.indices.contains(index)
        else {
            return nil
        }

        // node.image 是弱引用：已渲染的节点可能由 Page View 强持有图片而弱引用已失效。
        // 先看当前 View 是否已在展示图片，避免误判为未加载而重新下发任务（图片命中缓存、
        // GIF 重新解帧）；窗口内但尚未渲染的节点仍会重发，属已知边界。
        let hasDisplayedImage = nodes[index].image != nil
            || visibleViews[id]?.hasLoadedImage == true
        guard !hasDisplayedImage || nodes[index].imageDisplayMode != imageDisplayMode else {
            return nil
        }
        guard nodes[index].failure == nil else {
            return nil
        }
        guard nodes[index].page.resolvedPage != nil
            || priority == .visible
            || manifestPreloadRange?.contains(index) == true
        else {
            return nil
        }
        guard pageTasks[id] == nil else {
            return nil
        }

        return PageLoadContext(
            pageAccess: pageAccess,
            imageDisplayMode: imageDisplayMode,
            slot: nodes[index].page,
        )
    }

    /// 只更新本批槽位的元信息；随后按既有图片窗口补齐至少 8 页，不下载整批图片。
    private func applyResolvedPages(_ pages: [ComicPage]) {
        var didResolveImageWindowPage = false
        var didResolveReportedPage = false
        for page in pages {
            let position = ReaderPagePosition(chapter: page.identity.chapter, index: page.index)
            if let index = nodeIndexByID[position], nodes[index].page.resolvedPage == nil {
                nodes[index].page.resolvedPage = page
                didResolveImageWindowPage = didResolveImageWindowPage || activeImageWindowPageIDs
                    .contains(position)
                didResolveReportedPage = didResolveReportedPage || reportedCurrentPageID == position
            }
        }
        if didResolveImageWindowPage {
            lastImagePreloadRange = nil
            resetRenderSignature()
            needsRender = true
            startDisplayLinkIfNeeded()
        }
        // 只有已上报的占位页取得真实身份时才补报；其它分页不重复发布当前页。
        if didResolveReportedPage {
            reportedCurrentPageID = nil
            reportCurrentPageIfNeeded(force: true)
            if !isUserScrollSequenceActive {
                reportStablePageIfNeeded()
            }
        }
    }

    /// 图片处理完成后立即提交显示和真实比例，不等待正式磁盘缓存写入。
    private func presentPageImage(
        id: ReaderPagePosition,
        page: ComicPage,
        image: UIImage,
        displayMode: ReaderPageImageDisplayMode,
        taskID: Int,
    ) {
        guard pageTasks[id]?.id == taskID,
              imageDisplayMode == displayMode,
              let index = nodeIndexByID[id],
              nodes.indices.contains(index),
              image.size.width > 0,
              image.size.height > 0
        else {
            return
        }

        // 清单返回后可能切走又切回同一章；为新节点补回真实身份，再显示旧任务的结果。
        if nodes[index].page.resolvedPage == nil {
            applyResolvedPages([page])
        }
        if nodes[index].image === image,
           nodes[index].imageDisplayMode == displayMode {
            return
        }

        foregroundRecoveryRetryPageIDs.remove(id)
        failedPageIDs.remove(id)
        nodes[index].failure = nil
        // 窗口外任务可以继续完成并写入缓存，但不在 Canvas 中长期保留解码图片。
        let shouldRetainImage = activeImageWindowPageIDs.contains(id)
        nodes[index].image = shouldRetainImage ? image : nil
        nodes[index].imageDisplayMode = shouldRetainImage ? displayMode : nil
        // 动画图不入 Kingfisher 内存缓存，窗口内的保留由节点强持有承担；
        // 静态图的窗口内保留仍由弱引用 + 内存缓存承担。
        let retainsAnimatedImage = shouldRetainImage && image.isReaderAnimatedImage
        nodes[index].retainedAnimatedImage = retainsAnimatedImage ? image : nil
        let nextAspectRatio = image.size.height / image.size.width
        if nodes[index].aspectRatio != nextAspectRatio {
            nodes[index].aspectRatio = nextAspectRatio

            if shouldRetainImage {
                pendingAspectRatioPageIDs.insert(id)
            } else {
                // 离屏节点没有参与当前局部布局，直接保存自身真实高度即可。
                nodes[index].height = height(for: nodes[index])
            }
        }

        // 离屏任务只负责完成缓存并记录比例；下次正常窗口更新时再合并高度，
        // 不为当前看不到的页面额外唤醒 CADisplayLink 和 UIKit 布局。
        guard shouldRetainImage else {
            return
        }

        resetRenderSignature()
        needsRender = true
        startDisplayLinkIfNeeded()
    }

    /// 正式写盘后清理任务，即使其所属章节已经离开当前展示窗口。
    private func finishPageLoad(
        id: ReaderPagePosition,
        taskID: Int,
    ) {
        guard pageTasks[id]?.id == taskID else { return }

        pageTasks[id] = nil
        foregroundRecoveryRetryPageIDs.remove(id)
    }

    /// 设置变更或退出造成的取消不标记为加载失败。
    private func finishPageCancellation(
        id: ReaderPagePosition,
        taskID: Int,
    ) {
        guard pageTasks[id]?.id == taskID else { return }

        pageTasks[id] = nil
        foregroundRecoveryRetryPageIDs.remove(id)

        let shouldReload = activeImageWindowPageIDs.contains(id)
        if shouldReload, let index = nodeIndexByID[id] {
            let priority: ReaderPageLoadPriority = lastVisibleRange?.contains(index) == true
                ? .visible
                : .preload
            loadPageIfNeeded(id, priority: priority)
        }
    }

    /// 单页失败只更新该节点，不清空其它已加载页面。
    private func finishPageFailure(
        id: ReaderPagePosition,
        failure: ReaderPageFailure,
        taskID: Int,
    ) {
        guard pageTasks[id]?.id == taskID else { return }

        pageTasks[id] = nil
        guard let index = nodeIndexByID[id] else { return }

        // App 恢复前已在执行的请求可能在恢复扫描之后才报错。
        // 这类页面只自动重试一次，避免遗留手动点击的失败占位，
        // 同时不把普通网络失败变成无限重试。离线失败无法重试，直接进入终止态。
        let wasRecoveryRetry = foregroundRecoveryRetryPageIDs.remove(id) != nil
        if wasRecoveryRetry, canRetryFailedPage {
            nodes[index].failure = nil
            if activeImageWindowPageIDs.contains(id) {
                let priority: ReaderPageLoadPriority = lastVisibleRange?.contains(index) == true
                    ? .visible
                    : .preload
                loadPageIfNeeded(id, priority: priority)
            }
            return
        }

        nodes[index].failure = failure
        // 只记录可重试的失败；离线终止态不需要前台恢复再试一次。
        if canRetryFailedPage {
            failedPageIDs.insert(id)
        }
        // 旧位置的失败仍保留供回看重试；只有挂载中的页面需要刷新失败占位。
        guard visibleViews[id] != nil else { return }

        resetRenderSignature()
        needsRender = true
        startDisplayLinkIfNeeded()
    }

    /// 用户只重试当前失败页，不重新请求整个章节。
    func retryPage(_ id: ReaderPagePosition) {
        guard let index = nodeIndexByID[id],
              nodes.indices.contains(index)
        else {
            return
        }

        failedPageIDs.remove(id)
        nodes[index].failure = nil
        AppLogger.debug(
            "用户重试页面，chapterID=\(id.chapter.chapterID)，pageID=\(id.index + 1)",
            category: "Reader.Page",
        )
        loadPageIfNeeded(id, priority: .visible)
        updatePageWindow(force: true)
    }

    /// App 从后台恢复后保留进行中的任务，并重试已失败或缺失的页面。
    ///
    /// 已显示图片和进行中任务保持不变；`pageTasks` 会阻止
    /// 当前窗口重新规划时创建重复请求。
    func recoverPageLoadsAfterAppBecomesActive() {
        let activeTaskCount = pageTasks.count
        // 恢复扫描只能看到当前已失败的页面。对此时仍在执行的
        // 窗口内请求留下一次性标记，覆盖它们稍后才失败的竞态。
        foregroundRecoveryRetryPageIDs = Set(pageTasks.keys)
            .intersection(activeImageWindowPageIDs)
        let failedPageCount = failedPageIDs.count
        // 只遍历真正失败的页面，不在 App 回到前台时
        // 扫描整部长章节；窗口外页面之后重新进入时也可自动加载。
        for id in failedPageIDs {
            guard let index = nodeIndexByID[id],
                  nodes.indices.contains(index)
            else {
                continue
            }

            nodes[index].failure = nil
        }
        failedPageIDs.removeAll(keepingCapacity: true)

        // 强制重新扫描当前图片窗口：进行中的任务保持不变，
        // 已失败或当前没有任务的缺图页面才会重新加载。
        lastImagePreloadRange = nil
        resetRenderSignature()
        updatePageWindow(force: true)

        AppLogger.debug(
            "App 恢复前台，重新扫描页面加载，active=\(activeTaskCount)，retryingFailed=\(failedPageCount)",
            category: "Reader.Page",
        )
    }
}

/// 已通过状态判断的一次页面加载输入。
private struct PageLoadContext {
    let pageAccess: ReaderPageAccess
    let imageDisplayMode: ReaderPageImageDisplayMode
    let slot: ReaderPageSlot
}
