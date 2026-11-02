
/// Reader 入口与阅读记录使用同一份来源无关的作品快照。
typealias ReaderComicSnapshot = LibraryComicSnapshot

/// 阅读入口使用的页面位置；首次阅读为 nil，继续阅读从记录的位置定位。
struct ReaderStartPosition: Hashable, Sendable {
    let pageIdentity: PageIdentity
    let pageIndex: Int
}

extension ReadingProgress {
    var readerStartPosition: ReaderStartPosition {
        ReaderStartPosition(pageIdentity: pageIdentity, pageIndex: pageIndex)
    }
}

/// 保存公共 Reader 菜单和相邻章定位所需的最小章节引用。
struct ReaderChapterReference: Hashable, Sendable {
    let identity: ChapterIdentity
    let title: String
}

/// 三来源共用的阅读入口：单章传一个引用，多章按最旧到最新排列。
/// 页面行为由章节列表决定，不额外传来源或单／多章模式。
struct ComicReaderInput: Hashable, Sendable {
    let comicSnapshot: ReaderComicSnapshot
    let startPosition: ReaderStartPosition?
    let chapters: [ReaderChapterReference]
    let initialChapterIdentity: ChapterIdentity
    let contentMode: ComicContentMode

    /// 返回 snapshot 中已经绑定来源的漫画 identity。
    var comicIdentity: ComicIdentity {
        comicSnapshot.identity
    }

    /// 返回 snapshot 中用于 Reader Toolbar 的标题。
    var comicTitle: String {
        comicSnapshot.title
    }

    /// 只接受同一漫画中身份唯一的非空章节列表，以及与初始章节匹配的可选恢复位置。
    init?(
        comicSnapshot: ReaderComicSnapshot,
        startPosition: ReaderStartPosition?,
        chapters: [ReaderChapterReference],
        initialChapterIdentity: ChapterIdentity,
        contentMode: ComicContentMode = .online,
    ) {
        guard !comicSnapshot.title.isEmpty,
              !chapters.isEmpty,
              initialChapterIdentity.comic == comicSnapshot.identity,
              chapters.contains(where: {
                  $0.identity == initialChapterIdentity
              })
        else {
            return nil
        }

        if let startPosition {
            guard startPosition.pageIdentity.chapter == initialChapterIdentity,
                  !startPosition.pageIdentity.pageID.isEmpty,
                  startPosition.pageIndex >= 0
            else {
                return nil
            }
        }

        let comicIdentity = comicSnapshot.identity
        var chapterIdentities = Set<ChapterIdentity>()
        for chapter in chapters {
            guard chapter.identity.comic == comicIdentity,
                  !chapter.identity.chapterID.isEmpty,
                  chapterIdentities.insert(chapter.identity).inserted
            else {
                return nil
            }
        }

        self.comicSnapshot = comicSnapshot
        self.startPosition = startPosition
        self.chapters = chapters
        self.initialChapterIdentity = initialChapterIdentity
        self.contentMode = contentMode
    }
}
