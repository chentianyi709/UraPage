import Foundation

/// 从绅士 Reader 返回的 JavaScript 中读取服务端给出的有序图片地址。
enum ShenshiReaderScriptParser {
    /// 只解析 `mReader.initData` 的 JSON 参数，不执行网页脚本。
    static func pageURLStrings(from script: String) throws -> [String] {
        guard let marker = script.range(of: "mReader.initData"),
              let objectStart = script[marker.upperBound...].firstIndex(of: "{")
        else {
            throw ShenshiAPIError.invalidResponse
        }

        let object = try enclosedObject(in: script, startingAt: objectStart)
        let normalizedObject = removingTrailingCommas(from: object)
        guard let data = normalizedObject.data(using: .utf8) else {
            throw ShenshiAPIError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(Payload.self, from: data).pageURLs
        } catch {
            throw ShenshiAPIError.invalidResponse
        }
    }

    /// 提取 initData 的完整对象，并忽略字符串中的花括号。
    private static func enclosedObject(
        in script: String,
        startingAt objectStart: String.Index,
    ) throws -> String {
        var depth = 0
        var quote: Character?
        var isEscaped = false
        var index = objectStart

        while index < script.endIndex {
            let character = script[index]

            if let activeQuote = quote {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(script[objectStart ... index])
                }
            }
            index = script.index(after: index)
        }
        throw ShenshiAPIError.invalidResponse
    }

    /// 移除 JavaScript 允许、但 JSON 不接受的数组或对象尾逗号。
    private static func removingTrailingCommas(from value: String) -> String {
        var result = ""
        var quote: Character?
        var isEscaped = false
        var index = value.startIndex

        while index < value.endIndex {
            let character = value[index]

            if let activeQuote = quote {
                result.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
                result.append(character)
            } else if character == ",",
                      let nextCharacter = nextNonWhitespaceCharacter(in: value, after: index),
                      nextCharacter == "]" || nextCharacter == "}" {
                // 只跳过容器闭合前的逗号，其它数据保持原样。
            } else {
                result.append(character)
            }
            index = value.index(after: index)
        }
        return result
    }

    /// 返回指定位置之后的第一个非空白字符。
    private static func nextNonWhitespaceCharacter(
        in value: String,
        after index: String.Index,
    ) -> Character? {
        var nextIndex = value.index(after: index)
        while nextIndex < value.endIndex {
            let character = value[nextIndex]
            if !character.isWhitespace {
                return character
            }
            nextIndex = value.index(after: nextIndex)
        }
        return nil
    }
}

private extension ShenshiReaderScriptParser {
    /// 只声明 Reader 当前真正使用的脚本字段，其余字段变化不会影响解析。
    struct Payload: Decodable {
        let pageURLs: [String]

        enum CodingKeys: String, CodingKey {
            case pageURLs = "page_url"
        }
    }
}
