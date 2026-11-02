import Foundation

/// 为各模块提供格式统一、仅在 Debug 构建中输出的控制台日志。
///
/// 只用于本地诊断；日志内容不得包含 Token、Cookie、请求 URL、
/// 响应正文或用户资料。
enum AppLogger {
    /// 输出调试信息，例如临时状态或流程细节。
    static func debug(
        _ message: @autoclosure () -> String,
        category: String = "General",
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line,
    ) {
        log(.debug, message, category: category, file: file, function: function, line: line)
    }

    /// 输出普通运行信息，例如一次任务成功完成。
    static func info(
        _ message: @autoclosure () -> String,
        category: String = "General",
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line,
    ) {
        log(.info, message, category: category, file: file, function: function, line: line)
    }

    /// 输出需要关注但不阻断当前流程的警告信息。
    static func warning(
        _ message: @autoclosure () -> String,
        category: String = "General",
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line,
    ) {
        log(.warning, message, category: category, file: file, function: function, line: line)
    }

    /// 输出导致当前操作失败的错误信息。
    static func error(
        _ message: @autoclosure () -> String,
        category: String = "General",
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line,
    ) {
        log(.error, message, category: category, file: file, function: function, line: line)
    }

    /// 四个级别共用同一输出路径；日志文本只在 Debug 构建中求值（所以这里收普通闭包）。
    private static func log(
        _ level: Level,
        _ message: () -> String,
        category: String,
        file: StaticString,
        function: StaticString,
        line: UInt,
    ) {
        #if DEBUG
            // 用本地时区并带毫秒：与 Xcode／控制台行首时间戳同一时区，便于对齐事件顺序。
            let timestamp = Date().formatted(
                Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current),
            )
            Swift.print(
                "[\(timestamp)][\(level.rawValue)][\(category)] \(message()) — \(file):\(line) \(function)",
            )
        #endif
    }

    /// 把耗时折算成毫秒文本，避免日志里出现科学计数法、便于直接比较。
    static func milliseconds(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.1f ms", seconds * 1000)
    }

    /// 日志级别；输出格式与控制台检索习惯保持一致。
    private enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }
}
