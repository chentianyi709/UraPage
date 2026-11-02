import Foundation

extension DownloadManager {
    /// 构建导出一个已下载完成作品的计划：展示名称、封面文件与各章节页面文件位置。
    ///
    /// 只有作品聚合状态为 `completed`（所选章节与封面全部落盘）才可导出；正在下载、暂停、
    /// 失败或没有记录都按未完成处理，不把不完整数据当成可导出内容。构建计划时再次核对
    /// 全部章节记录、本地封面，以及每章 manifest 的页数与连续序号；任何缺失或损坏都按
    /// `incompleteAssets` 拒绝，避免导出半成品。
    /// 计划一次性取出章节清单与页面路径，导出器随后只做顺序读取，不再访问持久化或网络。
    func makeExportPlan(for comic: ComicIdentity) async throws -> ComicExportPlan {
        let status = try await persistence().downloadStatus(for: comic)
        guard let summary = status.summary, summary.state == .completed else {
            throw ComicExportError.notCompleted
        }
        guard !status.chapters.isEmpty,
              status.chapters.allSatisfy({ $0.state == .completed })
        else {
            throw ComicExportError.incompleteAssets
        }

        do {
            // 完成态必须同时有本地封面；没有封面文件的「完成」记录按资产不完整处理，
            // 不静默导出缺少封面的压缩包。
            guard case let .downloaded(reference?) = summary.cover else {
                throw ComicExportError.incompleteAssets
            }

            let coverFileURL = try DownloadAssetPaths.coverURL(for: reference)

            var chapters: [ComicExportChapter] = []
            var totalPageCount = 0
            for record in status.chapters {
                // 清单是页面的唯一索引：页数必须等于总数且序号从 0 连续，缺页时不导出半成品。
                guard let manifest = try await assetStore.loadManifest(for: record.identity) else {
                    throw ComicExportError.incompleteAssets
                }

                let entries = manifest.pages.sorted { $0.index < $1.index }
                guard entries.count == manifest.totalPageCount,
                      entries.enumerated().allSatisfy({ $0.offset == $0.element.index })
                else {
                    throw ComicExportError.incompleteAssets
                }

                var pages: [URL] = []
                pages.reserveCapacity(entries.count)
                for entry in entries {
                    let pageURL = try await assetStore.pageDataURL(for: entry, chapter: record.identity)
                    pages.append(pageURL)
                }

                chapters.append(ComicExportChapter(title: record.title, pages: pages))
                totalPageCount += pages.count
            }

            return ComicExportPlan(
                title: summary.title,
                coverFileURL: coverFileURL,
                chapters: chapters,
                totalPageCount: totalPageCount,
            )
        } catch let error as ComicExportError {
            throw error
        } catch {
            // 清单损坏、资产路径失效等资产侧错误统一按「本地资产不完整」反馈，不落到笼统的读写失败。
            AppLogger.warning(
                "导出计划构建失败，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            throw ComicExportError.incompleteAssets
        }
    }
}
