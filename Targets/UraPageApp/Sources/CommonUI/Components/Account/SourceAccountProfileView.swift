import SwiftUI

/// 账号资料页的资料头：头像槽位（来源 Logo 或远程头像）+ 展示名。
struct SourceAccountProfileHeader<Avatar: View>: View {
    let displayName: String

    /// 是否为头像加圆角表面与阴影：来源 Logo 需要，远程头像（自带圆形裁剪）不需要。
    let usesSurfaceBackground: Bool

    /// 头像槽位；来源提供 104pt 的内容。
    @ContentBuilder let avatar: () -> Avatar

    var body: some View {
        VStack(spacing: 16) {
            avatarView

            Text(displayName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
    }

    /// 头像：来源 Logo 需要圆角表面与阴影，远程头像（自带圆形裁剪）不需要。
    @ContentBuilder
    private var avatarView: some View {
        if usesSurfaceBackground {
            avatar()
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.surfaceElevated)
                        .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 12)
                }
        } else {
            avatar()
        }
    }
}

/// 账号资料页的一条只读资料行。
struct SourceAccountDetailRow: Identifiable {
    /// 由来源按字段语义提供，不随展示值改变。
    let id: String
    let title: String
    let value: String
}

/// 账号资料行的圆角分组：行间分隔线 + 表面色。
struct SourceAccountDetailRows: View {
    let rows: [SourceAccountDetailRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.enumerated(), id: \.element.id) { index, row in
                if index > 0 {
                    Divider()
                        .padding(.leading, 16)
                }

                detailRow(row)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.surfaceElevated)
        }
    }

    /// 一个只读资料行。
    private func detailRow(_ row: SourceAccountDetailRow) -> some View {
        HStack(spacing: 16) {
            Text(row.title)
                .foregroundStyle(Color.textSecondary)

            Spacer(minLength: 16)

            Text(row.value)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }
}
