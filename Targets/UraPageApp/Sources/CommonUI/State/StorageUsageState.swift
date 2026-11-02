/// 磁盘占用读取的三态；图片缓存与下载资产共用。
///
/// 只承载读取结果，大小文案与图标由页面映射；读取失败必须与「占用为 0」区分，
/// 不能把失败显示成空。
enum StorageUsageState: Equatable {
    /// 尚未读到（首次进入或正在读取）。
    case loading

    /// 当前占用字节数。
    case available(bytes: Int)

    /// 读取失败：占用不可用，页面以失败图标提示。
    case failed
}
