import Foundation

/// 导出内容的路径命名规则。
///
/// 下载资产的文件名是来源身份的摘要、内容格式不落库；导出时由 `DownloadedComicExporter`
/// 按内容识别格式，这里只负责目录与文件名的清洗、长度限制。
enum ComicExportNaming {
    /// 单个路径组件的 UTF-8 字节上限；给扩展名、层级与压缩包内路径留出余量。
    private static let maxComponentBytes = 120

    /// 文件名中不能出现的字符；统一替换为下划线，避免剪切板复制等场景下无法落盘。
    private static let illegalCharacters: Set<Unicode.Scalar> = [
        "/",
        "\\",
        ":",
        "*",
        "?",
        "\"",
        "<",
        ">",
        "|",
    ]

    /// Windows 保留设备名；作为文件基名（第一个点之前的完整组件）时加下划线前缀。
    private static let reservedNames: Set<String> = [
        "con",
        "prn",
        "aux",
        "nul",
        "com1",
        "com2",
        "com3",
        "com4",
        "com5",
        "com6",
        "com7",
        "com8",
        "com9",
        "lpt1",
        "lpt2",
        "lpt3",
        "lpt4",
        "lpt5",
        "lpt6",
        "lpt7",
        "lpt8",
        "lpt9",
    ]

    /// 清洗一个路径组件：替换非法字符与控制字符、去掉首尾空白与点前缀、按字节截断。
    ///
    /// 同时处理 Windows 的文件名限制（结尾的点与空格、保留设备名），
    /// 保证导出包在 Windows 解压时不会失败或被静默改名。
    /// `fallback` 用于清洗后为空的情况（例如章节标题全是非法字符），保证目录名始终可用。
    static func sanitizedComponent(_ raw: String, fallback: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F || illegalCharacters.contains(scalar) {
                scalars.append("_")
            } else {
                scalars.append(scalar)
            }
        }

        var name = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        // 前导点会生成隐藏项，"." 与 ".." 更是路径本身，直接去掉。
        while name.hasPrefix(".") {
            name.removeFirst()
        }
        name = removingTrailingDotsAndSpaces(from: name)
        guard !name.isEmpty else { return fallback }

        // 保留名按第一个点之前的基名判断（例如 "CON.txt" 同样不可用）。
        let baseName = name.prefix { $0 != "." }.lowercased()
        if reservedNames.contains(baseName) {
            name = "_" + name
        }

        let result = truncated(name, limit: maxComponentBytes, fallback: fallback)
        // 截断可能刚好停在点或空格之前；再做一次结尾清洗，避免 Windows 解压时静默改名。
        let cleaned = removingTrailingDotsAndSpaces(from: result)
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// Windows 会丢弃结尾的点与空格；去掉它们，保证解压后的文件名与包内一致。
    private static func removingTrailingDotsAndSpaces(from value: String) -> String {
        var result = value
        while result.hasSuffix(".") || result.hasSuffix(" ") {
            result.removeLast()
        }
        return result
    }

    /// 章节目录名：三位序号 + 空格 + 章节名，保证按名称排序即阅读顺序。
    static func chapterDirectoryName(position: Int, title: String) -> String {
        let name = sanitizedComponent(title, fallback: "章节")
        return String(format: "%03d %@", position, name)
    }

    /// 封面文件名：固定基名 `cover` + 识别出的扩展名。
    static func coverFileName(extension fileExtension: String) -> String {
        "cover.\(fileExtension)"
    }

    /// 页文件名：三位序号 + 识别出的扩展名，超过 999 页时按自然位数继续。
    static func pageFileName(position: Int, extension fileExtension: String) -> String {
        String(format: "%03d.%@", position, fileExtension)
    }

    /// 按字符逐个累加 UTF-8 字节数截断，避免从字符中间切断。
    private static func truncated(_ value: String, limit: Int, fallback: String) -> String {
        var byteCount = 0
        var result = ""
        for character in value {
            let size = character.utf8.count
            guard byteCount + size <= limit else { break }

            byteCount += size
            result.append(character)
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
