import Foundation

/// 一次已完成的来源服务器线路切换。
///
/// 只在 Host 操作成功且地址确实变化后发布；重复选择当前地址与失败的操作都不发布，
/// 读取继续使用原环境。事件流由每个来源的稳定 Client 持有，订阅方负责在生命周期结束时取消。
struct SourceHostChange: Sendable {}
