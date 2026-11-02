import SwiftUI

/// 搜索筛选弹窗（对应旧项目 Bika 搜索筛选 Sheet）：在独立 Sheet 中暂存多选分类。
///
/// 分类目录来自本源分类接口：加载中显示胶囊骨架（公共 `CapsuleSkeletonFlow`）、失败用公共失败态（插图＋说明＋重试）。
/// 分类以**胶囊**多选展示（选中填充品牌色、未选中偏灰底）；「不限分类」放在底部安全区插入区
/// （`safeAreaInset`＋`glassEffect` 玻璃按钮，当前无选择时品牌色 tint）。
/// 草稿未变时「应用」不可用。
struct BikaSearchFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 筛选弹窗使用的分类目录（与搜索页共用同一加载模型）。
    let categories: SourceValueLoadModel<[BikaComicCategory]>

    /// 把草稿交回搜索页。
    let onApply: (Set<BikaComicCategory>) -> Void

    @State private var selectedCategories: Set<BikaComicCategory>

    private let initialCategories: Set<BikaComicCategory>

    /// 使用页面已提交的筛选值创建可取消草稿。
    init(
        initialCategories: Set<BikaComicCategory>,
        categories: SourceValueLoadModel<[BikaComicCategory]>,
        onApply: @escaping (Set<BikaComicCategory>) -> Void,
    ) {
        self.categories = categories
        self.onApply = onApply
        self.initialCategories = initialCategories
        _selectedCategories = State(initialValue: initialCategories)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    unlimitedButton
                }
                .navigationTitle("搜索筛选")
                .navigationBarTitleDisplayMode(.inline)
                // 与来源设置弹窗一致：导航栏底色隐藏、sheet 形状底色跟随主题。
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: dismiss.callAsFunction) {
                            Image(systemName: "xmark")
                                .foregroundStyle(Color.textPrimary)
                        }
                        .tint(Color.textPrimary)
                        .accessibilityLabel("取消")
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: apply) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.textPrimary)
                        }
                        .disabled(!hasChanges)
                        .tint(Color.textPrimary)
                        .accessibilityLabel("应用筛选")
                    }
                }
        }
        .appNavigationBarScrollEdgeEffect()
        .presentationDetents([.fraction(3 / 4)])
        .presentationBackground(Color.pageBackground)
        .task {
            categories.loadIfNeeded()
        }
    }

    /// 草稿是否已与页面当前筛选不同。
    private var hasChanges: Bool {
        selectedCategories != initialCategories
    }

    /// 按分类加载状态分发：加载/失败/空态居中，有数据时展示可滚动的多选胶囊。
    @ContentBuilder
    private var content: some View {
        switch categories.loadState {
        case .idle, .loading:
            scrollFlow {
                CapsuleSkeletonFlow(horizontalPadding: 14, verticalPadding: 8, font: .subheadline)
            }
            .skeletonLoadingEffect()

        case let .failed(error):
            LoadErrorView(title: "分类加载失败", message: error.message) {
                categories.retry()
            }

        case .loaded:
            if categories.items.isEmpty {
                Text("暂无可用分类")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            } else {
                scrollFlow {
                    WrappingFlowLayout(
                        horizontalSpacing: 8,
                        verticalSpacing: 8,
                    ) {
                        ForEach(categories.items) { category in
                            capsuleButton(
                                title: category.title,
                                isSelected: selectedCategories.contains(category),
                            ) {
                                toggle(category)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 引导区/正文共用的滚动容器：内容左对齐、统一内边距并隐藏滚动条。
    private func scrollFlow(@ContentBuilder _ content: () -> some View) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    /// 底部「不限分类」玻璃按钮：高 44、宽为 sheet 一半、水平居中；选中（即当前无选择）时品牌色 tint。
    private var unlimitedButton: some View {
        Button {
            selectedCategories.removeAll()
        } label: {
            Text("不限分类")
                .font(.body)
                .lineLimit(1)
                .foregroundStyle(selectedCategories.isEmpty ? Color.textOnPrimary : Color.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(
                    selectedCategories.isEmpty ? .regular.tint(Color.brandPrimary) : .regular,
                    in: .capsule,
                )
        }
        .buttonStyle(.plain)
        .frame(height: 44)
        .containerRelativeFrame(.horizontal) { length, _ in length / 2 }
        .accessibilityLabel("不限分类")
        .accessibilityAddTraits(selectedCategories.isEmpty ? [.isSelected] : [])
    }

    /// 创建一个支持多选状态的分类胶囊：选中填充品牌色，未选中用中性填充色。
    private func capsuleButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isSelected ? Color.textOnPrimary : Color.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.brandPrimary : Color.fillNeutral,
                    in: Capsule(),
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// 在草稿中切换一个服务端分类。
    private func toggle(_ category: BikaComicCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    /// 把草稿交给搜索页后由 Sheet 自行关闭。
    private func apply() {
        onApply(selectedCategories)
        dismiss()
    }
}
