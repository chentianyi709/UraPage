import Alamofire
import Foundation

extension JMComicSourceClient {
    /// 请求禁漫首页推广分区，并整理为页面直接使用的展示模型。
    ///
    /// 分区是单次请求的静态列表，不做分区或漫画去重；坏卡片只跳过自身。
    func homeSections() async throws -> [JMComicHomeSection] {
        let sections = try await read { state in
            try await state.session
                .request("/promote", method: .get)
                .jmComicDecodedResponse(as: [JMComicHomeSectionDTO].self)
        }

        // 与产品一致，小说和资料库分区不属于漫画首页展示内容。
        let visibleSections = sections.filter {
            $0.type != "novels" && $0.type != "library"
        }

        return visibleSections.map(makeHomeSection)
    }

    /// 请求禁漫随机推荐的一批漫画，用于首页顶部的「随机推荐」分区。
    ///
    /// 服务端返回的是同一批近期作品的打乱顺序：反复请求只改变顺序，不换作品，
    /// 因此这里按单次请求的静态列表处理，不做去重；坏卡片只跳过自身。
    func randomRecommendComics() async throws -> [ComicListItem] {
        let comics = try await read { state in
            try await state.session
                .request("/random_recommend", method: .get)
                .jmComicDecodedResponse(as: [JMComicListItemDTO].self)
        }

        return SourceItemMapping
            .compactMap(comics, category: "JM.Home") { makeJMComicListItem(from: $0) }
    }

    /// 将首页分区 DTO 转换为不暴露接口字段的展示值。
    private func makeHomeSection(from section: JMComicHomeSectionDTO) -> JMComicHomeSection {
        JMComicHomeSection(
            id: section.id,
            title: Self.normalizedHomeSectionTitle(section.title),
            // 单次请求的静态分区不做去重；坏卡片只跳过自身。
            comics: SourceItemMapping
                .compactMap(section.content, category: "JM.Home") { makeJMComicListItem(from: $0) },
            navigation: Self.homeSectionNavigation(for: section),
        )
    }

    /// 把服务端分区类型映射为 App 可穷尽处理的来源专属语义。
    private static func homeSectionNavigation(for section: JMComicHomeSectionDTO)
        -> JMComicHomeSectionNavigation {
        if section.type.contains("category_id"), !section.slug.isEmpty {
            return .category(slug: section.slug)
        }
        if section.type == "promote" {
            guard !section.id.isEmpty else {
                return .none
            }

            return section.id == "26" ? .weekly : .promotion
        }
        return .none
    }

    /// 去掉服务端标题中的右滑提示，保留其余原文。
    private static func normalizedHomeSectionTitle(_ title: String) -> String {
        guard let arrowIndex = title.firstIndex(of: "→") else {
            return title
        }

        return String(title[..<arrowIndex]).trimmingCharacters(in: .whitespaces)
    }
}
