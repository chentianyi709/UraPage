import Alamofire
import Foundation

/// 描述禁漫业务 API 返回的未解密外层包装。
struct JMComicAPIResponseEnvelope: Decodable {
    let code: Int
    let data: String?
    let msg: String?
}

extension DataRequest {
    /// 解析并校验禁漫外层响应，适用于只需确认业务调用成功的接口。
    ///
    /// 允许成功响应的 `data` 为 `nil`，调用方仍可从返回值读取 `msg`。
    func jmComicValidatedResponse() async throws -> JMComicAPIResponseEnvelope {
        // 先交给 Alamofire 校验 HTTP 状态码，仅对成功响应继续处理响应体。
        let responseData = try await validate(statusCode: 200 ..< 300)
            .serializingData()
            .value

        // 服务端先返回未加密的外层 JSON；业务数据密文位于其 `data` 字段。
        let envelope: JMComicAPIResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(JMComicAPIResponseEnvelope.self, from: responseData)
        } catch {
            throw JMComicAPIError.invalidResponse
        }

        // HTTP 成功不代表业务成功，还需校验外层业务状态码。
        guard envelope.code == 200 else {
            throw JMComicAPIError.serverRejected(code: envelope.code, message: envelope.msg)
        }

        return envelope
    }

    /// 校验禁漫响应包装，解密 `data` 并解码成当前接口声明的 DTO。
    func jmComicDecodedResponse<Response: Decodable & Sendable>(
        as responseType: Response.Type,
    ) async throws -> Response {
        let envelope = try await jmComicValidatedResponse()

        guard let encryptedData = envelope.data, !encryptedData.isEmpty else {
            throw JMComicAPIError.missingEncryptedData
        }

        // Tokenparam 第一段是本次请求时间戳，可重建与请求 Token 相同的动态密钥。
        guard let timestamp = request?.value(forHTTPHeaderField: "Tokenparam")?
            .split(separator: ",")
            .first
            .flatMap({ Int($0) })
        else {
            throw JMComicAPIError.invalidConfiguration
        }

        return try await JMComicResponsePayloadWorker.decode(
            Response.self,
            from: encryptedData,
            timestamp: timestamp,
        )
    }
}

/// 解密与 DTO 解码都是纯计算；放到并发执行器，不占用来源 Client 状态 actor。
private enum JMComicResponsePayloadWorker {
    @concurrent
    static func decode<Response: Decodable & Sendable>(
        _ responseType: Response.Type,
        from base64Cipher: String,
        timestamp: Int,
    ) async throws -> Response {
        let decryptedData = try JMComicAESCipher.decryptAPIResponse(base64Cipher, timestamp: timestamp)

        do {
            return try JSONDecoder().decode(responseType, from: decryptedData)
        } catch {
            throw JMComicAPIError.invalidResponse
        }
    }
}
