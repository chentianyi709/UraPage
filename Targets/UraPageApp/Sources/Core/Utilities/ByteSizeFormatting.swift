import Foundation

/// 把字节数量格式化为便于阅读的展示文案（B／KB／MB／GB）。
///
/// 供需要展示字节数量的位置复用，避免各处重复堆 `String(format:)`；
/// 粒度固定：GB 两位小数、MB 一位小数、KB 取整，不足 1 KB 时用整数 B。
enum ByteSizeFormatting {
    /// 1 GB 的字节数；GB 展示与按 GB 换算磁盘上限等场景共用。
    static let bytesPerGB = 1024 * 1024 * 1024

    /// 将字节数量格式化为展示文案。
    ///
    /// - Parameter bytes: 需要展示的字节数。
    static func formatted(_ bytes: Int) -> String {
        let count = Double(bytes)
        if count >= Double(bytesPerGB) {
            return String(format: "%.2f GB", count / Double(bytesPerGB))
        }

        if count >= 1024 * 1024 {
            return String(format: "%.1f MB", count / (1024 * 1024))
        }

        if count >= 1024 {
            return String(format: "%.0f KB", count / 1024)
        }

        return "\(bytes) B"
    }
}
