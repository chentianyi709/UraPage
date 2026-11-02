import Foundation

extension UserDefaults {
    /// 读取属性列表支持的值；缺失或类型不匹配时返回 nil。
    func storedValue<Value>(forKey key: String) -> Value? {
        object(forKey: key) as? Value
    }

    /// 读取属性列表支持的值；缺失或类型不匹配时返回调用方提供的默认值。
    func storedValue<Value>(forKey key: String, default defaultValue: @autoclosure () -> Value) -> Value {
        storedValue(forKey: key) ?? defaultValue()
    }

    /// 读取以 String raw value 保存的类型；缺失或值无法识别时返回默认值。
    ///
    /// UserDefaults 跨 App 版本保留：无法识别的档位按首次使用默认值处理，不以崩溃暴露损坏设置。
    func storedRawRepresentable<Value: RawRepresentable>(
        forKey key: String,
        default defaultValue: @autoclosure () -> Value,
    ) -> Value where Value.RawValue == String {
        guard let rawValue: String = storedValue(forKey: key) else {
            return defaultValue()
        }

        return Value(rawValue: rawValue) ?? defaultValue()
    }

    /// 读取以 JSON Data 保存的 Codable 值；数据缺失或无法解码时返回 nil。
    func storedCodable<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(type, from: data)
    }

    /// 将 Codable 值编码为 JSON Data；编码失败时不修改已有值。
    func setCodable(_ value: some Encodable, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        set(data, forKey: key)
    }
}
