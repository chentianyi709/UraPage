import Foundation

/// 把一组字符串组件编码成无歧义的二进制 key，供数据库组合键与文件 key 复用。
///
/// 不能使用分隔符或裸字符串拼接：那样不同组件组合可能产生相同结果。
/// 编码格式：
///
/// ```text
/// 1 字节版本号
/// 8 字节大端组件数量
/// 每个组件：8 字节大端 UTF-8 字节长度 + 原始字节
/// ```
///
/// 调用方按各自 contract 决定是否再对结果计算 SHA-256。
enum IdentityKeyEncoder {
    /// 当前编码版本；新增版本时必须保留旧版本实现，保证已产生的 key 稳定。
    private static let version: UInt8 = 1

    /// 使用 v1 格式编码组件序列。
    ///
    /// - Parameter components: 按业务顺序排列的稳定组件，例如 `[sourceID, comicID, chapterID]`。
    /// - Returns: 不含分隔符歧义的二进制数据。
    static func v1(_ components: [String]) -> Data {
        var data = Data()
        data.append(version)
        appendBigEndian(UInt64(components.count), to: &data)
        for component in components {
            let bytes = Data(component.utf8)
            appendBigEndian(UInt64(bytes.count), to: &data)
            data.append(bytes)
        }
        return data
    }

    /// 以大端序追加一个 64 位无符号整数。
    private static func appendBigEndian(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { buffer in
            data.append(contentsOf: buffer)
        }
    }
}
