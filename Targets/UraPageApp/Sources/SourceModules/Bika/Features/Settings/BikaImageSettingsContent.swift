import SwiftUI

/// 哔咔「漫画源设置」里的图片设置项：非阅读图片清晰度与 CDN 加速开关。
///
/// 由页面放进同一个「漫画源设置」列表分区（不再自带分组）。两个偏好都由
/// `BikaSourcePreferences` 持久化、由 `BikaServices` 读写；
/// 偏好对象不是可观察对象，直接绑定服务时控件在切好后仍会显示切换前的值，
/// 因此这里在首次出现时读入初值、由视图保存编辑期间的值，变更后再写回同一份服务状态。
/// 清晰度只作用于浏览列表类图片（列表、首页、排行榜由页面图片服务取快照），
/// 阅读页图片固定原画、详情页封面不读该设置。
struct BikaImageSettingsContent: View {
    @Environment(\.sourceImageRequestInvalidation) private var imageRequestInvalidation

    let services: BikaServices

    @State private var usesImageCDNAcceleration: Bool
    @State private var browsingImageQuality: BikaImageQuality

    init(services: BikaServices) {
        self.services = services
        _usesImageCDNAcceleration = State(initialValue: services.selectedUsesImageCDNAcceleration())
        _browsingImageQuality = State(initialValue: services.selectedBrowsingImageQuality())
    }

    var body: some View {
        imageQualityRow
        imageCDNAccelerationRow
    }

    /// 同时作用于普通图片与阅读页图片的 CDN 加速开关。
    ///
    /// 切换会改变后续图片请求的线路：落盘偏好后让本源浏览图片的在途请求失效，
    /// 仍在加载的图片按新线路重新发起（与禁漫图源／线路切换同一处理）。
    /// 已缓存或已显示的图片不受影响——缓存 key 只有清晰度变体，不含 CDN 开关。
    private var imageCDNAccelerationRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("图片 CDN 加速", isOn: $usesImageCDNAcceleration)
                .onChange(of: usesImageCDNAcceleration) { _, newValue in
                    services.selectUsesImageCDNAcceleration(newValue)
                    imageRequestInvalidation.invalidateBrowsingImageRequests(for: services.sourceID)
                }

            Text("使用 go2778 中转封面与图片")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    /// 只影响浏览列表的清晰度选择；阅读页与详情页封面不读这个设置。
    private var imageQualityRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("非阅读图片清晰度")

                Spacer(minLength: 16)

                Picker("非阅读图片清晰度", selection: $browsingImageQuality) {
                    ForEach(BikaImageQuality.allCases, id: \.self) { quality in
                        Text(quality.displayTitle)
                            .tag(quality)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: browsingImageQuality) { _, newValue in
                    services.selectBrowsingImageQuality(newValue)
                }
            }

            Text("影响列表、排行榜等浏览图片；阅读页与详情页封面不受此设置影响")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
