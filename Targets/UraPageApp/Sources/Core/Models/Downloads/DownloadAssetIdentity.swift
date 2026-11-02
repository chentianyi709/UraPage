/// 持久化记录中用于定位资产目录的原始身份；来源不可识别时仍按原始字符串保留。
struct DownloadAssetIdentity: Hashable, Sendable {
    let sourceID: String
    let comicID: String
}
