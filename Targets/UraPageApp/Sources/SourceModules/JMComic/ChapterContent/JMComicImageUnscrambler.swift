import CryptoKit
import Foundation
import UIKit

/// 按禁漫协议验证图片，并还原需要解扰的水平切片。
enum JMComicImageUnscrambler {
    /// 返回已验证的原图数据，或已经解扰完成的位图。
    static func pagePayload(from data: Data, descriptor: JMComicPageDescriptor) throws -> SourcePagePayload {
        guard let aid = unscrambleAid(of: descriptor),
              let pageToken = pageToken(from: descriptor.url)
        else {
            return .encoded(data)
        }

        let sliceCount = sliceCount(aid: aid, pageToken: pageToken)
        guard sliceCount > 1 else {
            return .encoded(data)
        }

        // 只有真正需要解扰时才创建位图；原图由通用 Reader 完成唯一一次解码。
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw JMComicAPIError.invalidResponse
        }

        let restoredImage = restore(image, sliceCount: sliceCount)
        guard let restoredCGImage = restoredImage.cgImage else {
            throw JMComicAPIError.invalidResponse
        }

        return .decoded(restoredCGImage)
    }

    /// 返回需要解扰的章节漫画 ID；GIF 不解扰，未达服务端阈值的章节也不需要还原。
    private static func unscrambleAid(of descriptor: JMComicPageDescriptor) -> Int? {
        guard descriptor.url.pathExtension.lowercased() != "gif",
              let aid = Int(descriptor.aid),
              let threshold = Int(descriptor.scrambleID),
              aid >= threshold
        else {
            return nil
        }

        return aid
    }

    /// 从图片文件名保留补零后的页码，与服务端 MD5 规则保持一致。
    private static func pageToken(from url: URL) -> String? {
        let token = url.deletingPathExtension().lastPathComponent
        guard !token.isEmpty, token.allSatisfy(\.isNumber) else {
            return nil
        }

        return token
    }

    /// 按禁漫的漫画 ID 分段和 MD5 末字符计算切片数。
    private static func sliceCount(aid: Int, pageToken: String) -> Int {
        if aid < 268_850 {
            return 10
        }

        let digest = Insecure.MD5.hash(data: Data("\(aid)\(pageToken)".utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        guard let lastByte = hash.last?.asciiValue else {
            return 2
        }

        let remainder = aid <= 421_925 ? Int(lastByte) % 10 : Int(lastByte) % 8
        return (remainder + 1) * 2
    }

    /// 从原图底部向上取片，并从目标画布顶部向下重新组合。
    private static func restore(_ image: UIImage, sliceCount: Int) -> UIImage {
        guard let cgImage = image.cgImage, cgImage.height >= sliceCount else {
            return image
        }

        let width = cgImage.width
        let height = cgImage.height
        let baseHeight = height / sliceCount
        let remainder = height % sliceCount
        var sourceBottomY = height
        var canvasY = 0

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)

        return renderer.image { _ in
            for index in 0 ..< sliceCount {
                let sliceHeight = baseHeight + (index == 0 ? remainder : 0)
                sourceBottomY -= sliceHeight

                let sourceRect = CGRect(x: 0, y: sourceBottomY, width: width, height: sliceHeight)
                let drawRect = CGRect(x: 0, y: canvasY, width: width, height: sliceHeight)
                if let slice = cgImage.cropping(to: sourceRect) {
                    UIImage(cgImage: slice).draw(in: drawRect)
                }
                canvasY += sliceHeight
            }
        }
    }
}
