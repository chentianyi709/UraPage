import Foundation
import SwiftSoup

/// 从绅士网页资料页读取 App 展示需要的最小账号资料。
enum ShenshiAccountProfileHTMLParser {
    static func parse(_ html: String, username: String) throws -> ShenshiAccountProfile {
        do {
            let document = try SwiftSoup.parse(html)
            guard let nicknameInput = try document.select("input[name=user_nicename]").first() else {
                throw ShenshiAPIError.invalidResponse
            }

            let displayName = try nicknameInput.attr("value").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayName.isEmpty else {
                throw ShenshiAPIError.invalidResponse
            }

            return ShenshiAccountProfile(username: username, displayName: displayName)
        } catch let error as ShenshiAPIError {
            throw error
        } catch {
            throw ShenshiAPIError.invalidResponse
        }
    }
}
