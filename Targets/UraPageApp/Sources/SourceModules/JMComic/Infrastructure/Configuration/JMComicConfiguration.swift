import CryptoKit
import Foundation

/// 禁漫来源的固定协议常量与持久化标识符。
///
/// 只放不随构建环境变化、也不属于 App 全局的禁漫协议值；
/// 可变设置、当前 Host 与远端响应由各自 owner 管理。
/// 敏感值不写日志，能集中就集中，避免散落在请求构造处。
enum JMComicConfiguration {
    /// 业务 API 签名、响应解密与默认分流使用的固定协议值。
    enum API {
        /// 客户端协议版本，参与 `Tokenparam` 且服务端会校验。
        static let appVersion = "2.1.11"

        /// 生成动态 Token 与响应解密密钥所用的固定盐值。
        static let tokenSalt = "185Hcomic3PAPP7R"

        /// 兼容第二解密密钥所用的固定盐值（接口文档的「API 解密 Key 2」）。
        static let fallbackTokenSalt = "18comicAPPContent"

        /// 从未准备过远端 Setting 时使用的默认图片分流。
        static let defaultImageSourceKey = 1

        /// 使用请求时间戳生成 Token Header 与响应动态解密密钥。
        static func token(for timestamp: Int) -> String {
            let data = Data("\(timestamp)\(tokenSalt)".utf8)
            return SourceDigest.hex(Insecure.MD5.hash(data: data))
        }

        /// 兼容第二解密密钥：`md5(时间戳 + 备盐)`，主密钥失败后尝试。
        static func fallbackToken(for timestamp: Int) -> String {
            let data = Data("\(timestamp)\(fallbackTokenSalt)".utf8)
            return SourceDigest.hex(Insecure.MD5.hash(data: data))
        }
    }

    /// Host 协议的固定 bootstrap 信任根与解密材料。
    enum Host {
        /// 依次尝试的固定 HTTPS 入口，用于获取加密 Host 列表。
        static let bootstrapURLs = [
            URL(string: "https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt")!,
            URL(string: "https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt")!,
        ]

        /// Host 列表 AES-ECB 解密使用的 32 字节密钥。
        static let cipherKey = "6ae6b037507edb82ee4699827c4b4066"

        /// 固定的加密 Host 列表，只在 CDN 全部失败时作为当前进程兜底。
        static let fallbackHostCipher =
            "X+bnzYIcwF6C7Rd3T7njPM0aeKgOoB+o/+lwS/klMzdv/yrVPk0UikahXv/MGxHqaSCwOCfGQjX0QpMp" +
            "Sxvr4+vsg/4ohUY8jspsJ7gSoQU5ANBMM99J2WtKxGgIBLq9PjCaS/34KK9HSiLJdaXz40oGSEHkBl8L" +
            "0tTfPRC+dmPlp2CJ/97anZkSqForX+hTFgVoS0BZl/gXUQdF2njjAjgJwg13qbTJd3QB0CExaztlrC1Z" +
            "1QGhXNjxM0Zk5v8i8JoPtTe7LWW55r96oLJrDOG60uspZxlV+Jp3FOdRXFH++Mann1Vo88iv9kbTa1f1F" +
            "kaUCEgPpxNKmnCpnNUhNgCZExIlg7RcQQ6Ru+ys1D4+GAhA3Z1gUDMsYIit/bD8H30ZoBip59iW0Nx4h" +
            "aPYM5Pb9GyYRAkIJfQRP46w1JQXMPir0MCxMnvFahb0xzOULRx+WBrOe/oMKD1Dsohhxw=="
    }

    /// 禁漫列表分页的固定假设。
    enum Browse {
        /// 最新接口固定返回的完整页条数；用于判断是否还有下一页。
        static let latestPageSize = 80

        /// 周刊接口按当前页条目数量判断是否可能还有下一页。
        static let weeklyPageSize = 40
    }

    /// 禁漫图片协议的固定常量。
    enum Image {
        /// 服务端未返回封面时使用的默认相对路径与 `_3x4` 尺寸标记。
        ///
        /// 相对路径由图片服务基于当前图片 Host 解析；缓存身份不包含 Host。
        static func defaultCoverRelativePath(comicID: String) -> String {
            "media/albums/\(comicID)_3x4.jpg"
        }

        /// 服务端头像只返回文件名时补全的相对路径。
        ///
        /// 禁漫头像接口在部分场景只给文件名（不含目录），按来源协议补 `media/users/` 前缀；
        /// 完整 URL 或已含目录的 locator 不使用本规则。
        static func defaultAvatarRelativePath(fileName: String) -> String {
            "media/users/\(fileName)"
        }
    }

    /// 禁漫本地持久化 Key；Bundle Identifier 前缀由 `AppIdentifierNamespace` 生成，
    /// 版本段写在各 key 字符串里，读写留在各 owner。
    enum Storage {
        /// 上次登录成功后用于页面展示的非敏感账号资料。
        static let accountProfile = AppIdentifierNamespace.make("v1.account-profile.jm")

        /// 当前选择的图片分流数字。
        static let imageSource = AppIdentifierNamespace.make("v1.image-source.jm")

        /// GET 接口当前使用的内容语言。
        static let contentLanguage = AppIdentifierNamespace.make("v1.content-language.jm")

        /// 分类接口是否把分类名转换为繁体中文。
        static let usesTraditionalCategoryParameter = AppIdentifierNamespace.make(
            "v1.category-parameter-traditional.jm",
        )
    }
}
