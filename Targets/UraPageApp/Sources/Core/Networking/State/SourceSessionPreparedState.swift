import Alamofire

/// 绑定单个业务 Session 的来源准备状态。
///
/// 默认按该 Session 取消在途请求；来源实现只需暴露 `session`。
/// 这是来源基础设施的一部分，不是业务协议。
protocol SourceSessionPreparedState: SourceClientPreparedState {
    var session: Session { get }
}

extension SourceSessionPreparedState {
    func cancelInFlightRequests() {
        session.cancelAllRequests()
    }
}
