import Alamofire
import Foundation
import Synchronization

/// 独立推荐服务使用不携带哔咔凭证、签名和 Cookie 的 Session。
final class BikaPersonalizedRecommendationClient: Sendable {
    private let session: Session
    private let previousComicID: Mutex<String?>

    init() {
        let configuration = URLSessionConfiguration.af.ephemeral
        SourceConfiguration.Session.applyCookieFreeDefaults(to: configuration)

        session = Session(configuration: configuration)
        previousComicID = Mutex(
            UserDefaults.standard.string(forKey: BikaConfiguration.Storage.personalizedRecommendationOrigin),
        )
    }

    /// 取得服务端按顺序返回的作品 ID，去掉重复项与空值。
    func recommendationComicIDs(for comicID: String) async throws -> [String] {
        let response = try await session
            .request(
                BikaConfiguration.Recommendation.baseURL.appending(path: comicID),
                method: .get,
                parameters: ["limit": BikaConfiguration.Recommendation.requestLimit],
                encoding: URLEncoding(destination: .queryString),
            )
            .validate(statusCode: 200 ..< 300)
            .serializingDecodable(BikaPersonalizedRecommendationResponseDTO.self)
            .value
        guard response.code == 1 else {
            throw BikaAPIError.serverRejected(code: response.code)
        }

        var seenIDs = Set<String>()
        return response.recommendations.filter { !$0.isEmpty && seenIDs.insert($0).inserted }
    }

    /// 首次进入只保存起点；从不同作品进入下一详情时再发送跳转记录。
    func recordTransition(to comicID: String) async throws {
        let previous = previousComicID.withLock { storedID -> String? in
            let previous = storedID
            storedID = comicID
            UserDefaults.standard.set(
                comicID,
                forKey: BikaConfiguration.Storage.personalizedRecommendationOrigin,
            )
            return previous
        }
        guard let previous, previous != comicID else { return }

        _ = try await session
            .request(
                BikaConfiguration.Recommendation.baseURL.appending(path: "track"),
                method: .post,
                parameters: ["from_id": previous, "to_id": comicID],
                encoding: JSONEncoding.default,
            )
            .validate(statusCode: 200 ..< 300)
            .serializingData()
            .value
    }
}
