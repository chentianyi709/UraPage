// Reader 页面缓存键生成规则：
// 1. 只使用完整 PageIdentity：漫画源、作品 ID、章节 ID 和页面 ID。
// 2. 使用 Domain 唯一的 IdentityKeyEncoder.v1 生成无歧义字节序列。
// 3. 对组合结果计算 SHA-256，最终格式为 reader.page.v1.<摘要>。
// 4. 图片 URL、Host、查询参数、扩展名和禁漫解扰参数都不进入缓存键。
// 5. 这个 Key 只表示保留高清内容的正式磁盘项；ReaderPageImageLoader
//    会在其后追加显示模式，生成不落盘的短期内存变体。

import CryptoKit
import Foundation

/// 为在线 Reader 页面生成不暴露业务身份原文的稳定缓存键。
nonisolated enum ReaderPageCacheKey {
    /// 使用完整页面身份生成首个正式版本的 Reader 缓存键。
    static func make(for identity: PageIdentity) -> String {
        let components = [
            identity.chapter.comic.sourceID.rawValue,
            identity.chapter.comic.comicID,
            identity.chapter.chapterID,
            identity.pageID,
        ]
        let digest = SourceDigest.hex(SHA256.hash(data: IdentityKeyEncoder.v1(components)))

        return "reader.page.v1.\(digest)"
    }
}
