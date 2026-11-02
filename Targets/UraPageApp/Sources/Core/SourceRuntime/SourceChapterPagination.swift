import Foundation

/// 一个接口分页取得的公共页面与私有请求描述；坏条目跳过但不压缩后续页序号。
struct SourceChapterPageBatch<Descriptor: SourcePageDescriptor>: Sendable {
    let pages: [ComicPage]
    let descriptors: [Descriptor]
}

/// 来源提供分页换算所需的真实 limit 与请求；缓存、在途共享及取消由公共句柄管理。
/// batchIndex 为零基接口分页号，不是章节号或图片的 PageIdentity。
struct SourceChapterPagination<Descriptor: SourcePageDescriptor>: Sendable {
    let batchSize: Int
    let loadBatch: @Sendable (_ batchIndex: Int) async throws -> SourceChapterPageBatch<Descriptor>

    /// `batchSize` 是服务端每批条数，必须为正；否则分页偏移无法推进。
    init(
        batchSize: Int,
        loadBatch: @escaping @Sendable (_ batchIndex: Int) async throws -> SourceChapterPageBatch<Descriptor>,
    ) {
        precondition(batchSize > 0, "章节分页 batchSize 必须大于 0")
        self.batchSize = batchSize
        self.loadBatch = loadBatch
    }
}
