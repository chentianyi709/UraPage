import Foundation

/// 表示通用 User-Agent 生成器支持的客户端平台规则。
enum SourceUserAgentPlatform: String, Hashable, Sendable {
    case android
    case iOS
}

/// 按客户端平台生成并持久化稳定的移动端 Chrome User-Agent。
///
/// 不接收 `ComicSourceID`，也不知道具体来源；首次使用时生成并按平台隔离保存。
/// 生命周期固定为进程，actor 保护缓存；来源直接按平台读取，不逐层传递。
actor SourceUserAgentProvider {
    static let shared = SourceUserAgentProvider()

    private let userDefaults = UserDefaults.standard
    private var cachedUserAgents: [SourceUserAgentPlatform: String] = [:]

    private init() {}

    /// 返回指定平台在当前安装中使用的 User-Agent；尚未生成时创建并保存。
    func userAgent(for platform: SourceUserAgentPlatform) -> String {
        if let cachedUserAgent = cachedUserAgents[platform] {
            return cachedUserAgent
        }

        let storageKey = SourceConfiguration.Storage.userAgent(for: platform)
        if let storedUserAgent = userDefaults.string(forKey: storageKey), !storedUserAgent.isEmpty {
            cachedUserAgents[platform] = storedUserAgent
            return storedUserAgent
        }

        let userAgent = Self.makeUserAgent(for: platform)
        userDefaults.set(userAgent, forKey: storageKey)
        cachedUserAgents[platform] = userAgent
        return userAgent
    }

    private static func makeUserAgent(for platform: SourceUserAgentPlatform) -> String {
        switch platform {
        case .android:
            makeAndroidChromeUserAgent()
        case .iOS:
            makeIOSChromeUserAgent()
        }
    }

    /// 随机组合 Android、设备 Build 和 Chrome 版本，生成移动端 Chrome UA。
    private static func makeAndroidChromeUserAgent() -> String {
        let devices = [
            (version: "13", model: "Pixel 7", build: "TQ3A.230805.001"),
            (version: "14", model: "Pixel 8", build: "UQ1A.240205.004"),
            (version: "14", model: "SM-S9280", build: "UP1A.231005.007"),
            (version: "15", model: "Pixel 9", build: "AP3A.241005.015"),
        ]
        let chromeVersions = [
            "120.0.6099.144",
            "121.0.6167.101",
            "122.0.6261.105",
            "123.0.6312.80",
            "124.0.6367.82",
            "125.0.6422.147",
        ]
        // 数组都是非空字面量，直接按索引随机取，避免无意义的可选兜底。
        let device = devices[Int.random(in: devices.indices)]
        let chromeVersion = chromeVersions[Int.random(in: chromeVersions.indices)]

        return "Mozilla/5.0 (Linux; Android \(device.version); "
            + "\(device.model) Build/\(device.build)) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/\(chromeVersion) Mobile Safari/537.36"
    }

    /// 随机组合 iOS、Chrome 和 Mobile Build 版本，生成 iOS Chrome 标准格式的 UA。
    private static func makeIOSChromeUserAgent() -> String {
        let iosVersions = ["17_6", "18_0", "18_1", "18_2", "18_3", "18_4", "18_5", "18_6", "26_0"]
        let chromeVersions = [
            "120.0.6099.119",
            "121.0.6167.85",
            "122.0.6261.69",
            "123.0.6312.87",
            "124.0.6367.69",
            "125.0.6422.80",
        ]
        let buildVersions = ["15E148", "20G75", "21A329", "21E219", "22A3354", "22E240"]

        let iosVersion = iosVersions[Int.random(in: iosVersions.indices)]
        let chromeVersion = chromeVersions[Int.random(in: chromeVersions.indices)]
        let buildVersion = buildVersions[Int.random(in: buildVersions.indices)]

        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(iosVersion) like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "CriOS/\(chromeVersion) Mobile/\(buildVersion) Safari/604.1"
    }
}
