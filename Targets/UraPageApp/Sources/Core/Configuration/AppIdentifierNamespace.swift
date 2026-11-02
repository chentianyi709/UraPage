import Foundation

/// 使用当前 App 的 Bundle Identifier 为各模块生成统一的应用内标识符。
///
/// 只负责公共前缀算法；具体业务后缀由各模块 Configuration 提供，
/// 不在公共层保存业务后缀。
enum AppIdentifierNamespace {
    /// 当前 App 的 Bundle Identifier；缺失说明运行环境异常，无法安全生成持久化命名空间。
    ///
    /// 不提供硬编码兜底：错误的命名空间会把业务数据写到与工程配置不一致的位置。
    private static let bundleIdentifier: String = {
        guard let identifier = Bundle.main.bundleIdentifier else {
            preconditionFailure("缺少 Bundle Identifier：无法生成持久化命名空间")
        }

        return identifier
    }()

    /// 为具体用途生成完整标识符。
    ///
    /// 命名空间为 `<Bundle Identifier>.<suffix>`；**版本段写在每个 key 自己的字符串里**
    /// （suffix 形如 `"v1.selected-source"`）。这样某个配置发生破坏性变更时只递增对应 key 的
    /// 版本段，其它旧配置继续有效，不会因为统一版本号变化而一起失效。
    static func make(_ suffix: String) -> String {
        "\(bundleIdentifier).\(suffix)"
    }
}
