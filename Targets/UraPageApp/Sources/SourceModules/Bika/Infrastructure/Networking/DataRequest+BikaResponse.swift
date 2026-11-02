import Alamofire
import Foundation

/// 描述哔咔业务 API 的通用 JSON 响应包装。
struct BikaAPIResponseEnvelope<Response: Decodable & Sendable>: Decodable, Sendable {
    let code: Int
    let data: Response
}

/// 只解析哔咔响应的业务状态，避免错误响应被成功 DTO 结构阻断。
private struct BikaAPIResponseStatus: Decodable {
    let code: Int
}

/// 哔咔前台业务响应共用的业务码与 `data` 解码规则。
///
/// HTTP 状态校验与调用方语义相关（登录允许被拒响应并读取业务码），因此由调用方先行处理。
enum BikaResponsePayload {
    /// 读取响应体里的业务状态码；正文不是哔咔信封时为 `nil`，由调用方决定如何回落。
    static func businessCode(in responseData: Data) -> Int? {
        (try? JSONDecoder().decode(BikaAPIResponseStatus.self, from: responseData))?.code
    }

    /// 校验业务码为成功并解码当前接口声明的 `data`。
    ///
    /// 成功路径只解析一遍 JSON；只有整包解码失败时才单独读取业务码，
    /// 这样错误响应即使缺少成功 `data`，仍能区分来源拒绝与无效响应。
    @concurrent
    static func data<Response: Decodable & Sendable>(
        _ responseType: Response.Type,
        in responseData: Data,
    ) async throws -> Response {
        let envelope = try? JSONDecoder().decode(
            BikaAPIResponseEnvelope<Response>.self,
            from: responseData,
        )
        if let envelope {
            guard envelope.code == 200 else {
                throw BikaAPIError.serverRejected(code: envelope.code)
            }

            return envelope.data
        }

        guard let businessCode = businessCode(in: responseData) else {
            throw BikaAPIError.invalidResponse
        }
        guard businessCode == 200 else {
            throw BikaAPIError.serverRejected(code: businessCode)
        }

        // 业务成功但 `data` 无法按当前接口声明的 DTO 解码。
        throw BikaAPIError.invalidResponse
    }
}

extension DataRequest {
    /// 解析登录响应：HTTP 被拒时仍读取响应体里的业务码。
    ///
    /// 登录失败的 400/401 响应体里带业务码（例如凭证错误），普通接口的 `bikaDecodedResponse`
    /// 会先按 HTTP 状态拒绝、丢掉该业务码，登录文案就只能给通用提示；
    /// 这里优先取业务码、缺失时回落 HTTP 状态码，其余分支与普通接口一致。
    func bikaLoginDecodedResponse<Response: Decodable & Sendable>(
        as responseType: Response.Type,
    ) async throws -> Response {
        // 不做 HTTP 状态校验：被拒响应也要读正文取业务码。
        let responseData = try await serializingData().value

        if let statusCode = response?.statusCode, !(200 ..< 300).contains(statusCode) {
            throw BikaAPIError.serverRejected(
                code: BikaResponsePayload.businessCode(in: responseData) ?? statusCode,
            )
        }

        return try await BikaResponsePayload.data(Response.self, in: responseData)
    }

    /// 校验 HTTP 和哔咔业务状态，再解码当前接口声明的响应 DTO。
    ///
    /// 业务码在整包解码失败后按需独立解码：错误响应缺少成功 `data` 时，仍要能读到业务码。
    func bikaDecodedResponse<Response: Decodable & Sendable>(
        as responseType: Response.Type,
    ) async throws -> Response {
        let responseData = try await validate(statusCode: 200 ..< 300)
            .serializingData()
            .value

        return try await BikaResponsePayload.data(Response.self, in: responseData)
    }
}
