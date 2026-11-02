import Foundation

/// 生成标准 ZIP（stored，不压缩）容器，供「下载记录」导出使用。
///
/// 命名强调「写压缩包」而不是某种压缩算法：当前只实现 stored，未来若增加压缩也不会改变调用方语义。
///
/// 下载页与封面本身已是压缩格式（JPEG/PNG/WebP…），再压缩收益极低，因此统一用 stored，
/// 不为导出引入压缩依赖。条目路径一律 UTF-8（general purpose bit 11）；单条目大小、
/// 本地头偏移或中央目录超过 4 GiB 时自动写 ZIP64 扩展，不限制导出体积。
///
/// 每个条目的数据由调用方读取一次后直接传入（内存映射，不把整包放进内存）：先算 CRC，再写带 CRC
/// 的本地头与内容，因此没有 CRC 占位与回填，也不重复读盘。全部条目写完必须调用 `finish()` 写中央目录。
final class ZipArchiveWriter {
    private struct Entry {
        let name: Data
        let crc32: UInt32
        let size: UInt64
        let localHeaderOffset: UInt64
        /// 条目大小放不下 32 位，需要在本地头与中央目录写 ZIP64 大小字段。
        let sizeNeedsZip64: Bool
        /// 本地头偏移放不下 32 位，需要在中央目录写 ZIP64 偏移字段。
        let offsetNeedsZip64: Bool
        let dosDate: UInt16
        let dosTime: UInt16
    }

    /// 32 位字段放不下的占位值：字段被写为它时，真实值放进 ZIP64 扩展字段。
    private static let zip64Sentinel: UInt64 = 0xFFFF_FFFF

    /// 需要写 ZIP64 扩展的阈值；与占位值同源，但语义不同：一个是写入内容，一个是判断条件。
    private static let zip64Threshold: UInt64 = 0xFFFF_FFFF

    private let handle: FileHandle
    private var offset: UInt64 = 0
    private var entries: [Entry] = []
    private var isFinished = false

    init(destinationURL: URL) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destinationURL)
        guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw ComicExportError.cannotWriteArchive
        }

        handle = try FileHandle(forWritingTo: destinationURL)
    }

    deinit {
        try? handle.close()
    }

    /// 把一份数据按 `path` 相对路径写入压缩包；`path` 用 `/` 分隔且不带前导斜杠。
    ///
    /// 数据由调用方读取：同一份数据还要用于识别图片格式，避免同一文件被打开两次。
    func addData(_ data: Data, path: String, modificationDate: Date) throws {
        guard !isFinished else {
            throw ComicExportError.cannotWriteArchive
        }

        let size = UInt64(data.count)
        let crc32 = Self.crc32(data)
        let name = Data(path.utf8)
        let (dosDate, dosTime) = Self.dosDateTime(modificationDate)

        let sizeNeedsZip64 = size >= Self.zip64Threshold
        let offsetNeedsZip64 = offset >= Self.zip64Threshold
        let localHeaderOffset = offset

        var header = Data()
        header.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
        header.appendLittleEndian(UInt16(sizeNeedsZip64 ? 45 : 20))
        header.appendLittleEndian(UInt16(0x0800))
        header.appendLittleEndian(UInt16(0))
        header.appendLittleEndian(dosTime)
        header.appendLittleEndian(dosDate)
        header.appendLittleEndian(crc32)
        header.appendLittleEndian(UInt32(sizeNeedsZip64 ? Self.zip64Sentinel : size))
        header.appendLittleEndian(UInt32(sizeNeedsZip64 ? Self.zip64Sentinel : size))
        header.appendLittleEndian(UInt16(name.count))
        let extra = sizeNeedsZip64 ? Self.zip64Extra(uncompressedSize: size, compressedSize: size) : Data()
        header.appendLittleEndian(UInt16(extra.count))
        header.append(name)
        header.append(extra)

        try write(header)
        try handle.write(contentsOf: data)
        offset += size

        entries.append(Entry(
            name: name,
            crc32: crc32,
            size: size,
            localHeaderOffset: localHeaderOffset,
            sizeNeedsZip64: sizeNeedsZip64,
            offsetNeedsZip64: offsetNeedsZip64,
            dosDate: dosDate,
            dosTime: dosTime,
        ))
    }

    /// 写中央目录与结束记录；重复调用只生效一次。
    func finish() throws {
        guard !isFinished else { return }

        isFinished = true

        let centralDirectoryOffset = offset
        for entry in entries {
            try write(Self.centralDirectoryRecord(for: entry))
        }
        let centralDirectorySize = offset - centralDirectoryOffset
        let entryCount = UInt64(entries.count)

        // 0xFFFF 正好是 EOCD 的 ZIP64 哨兵值：条目数等于它时也必须写 ZIP64 记录，
        // 否则 reader 会去找 locator 却找不到。
        if entryCount >= 0xFFFF
            || centralDirectoryOffset >= Self.zip64Threshold
            || centralDirectorySize >= Self.zip64Threshold {
            let zip64EndOffset = offset
            var record = Data()
            record.append(contentsOf: [0x50, 0x4B, 0x06, 0x06])
            record.appendLittleEndian(UInt64(44))
            record.appendLittleEndian(UInt16(45))
            record.appendLittleEndian(UInt16(45))
            record.appendLittleEndian(UInt32(0))
            record.appendLittleEndian(UInt32(0))
            record.appendLittleEndian(entryCount)
            record.appendLittleEndian(entryCount)
            record.appendLittleEndian(centralDirectorySize)
            record.appendLittleEndian(centralDirectoryOffset)
            try write(record)

            var locator = Data()
            locator.append(contentsOf: [0x50, 0x4B, 0x06, 0x07])
            locator.appendLittleEndian(UInt32(0))
            locator.appendLittleEndian(zip64EndOffset)
            locator.appendLittleEndian(UInt32(1))
            try write(locator)
        }

        var end = Data()
        end.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        end.appendLittleEndian(UInt16(0))
        end.appendLittleEndian(UInt16(0))
        end.appendLittleEndian(UInt16(min(entryCount, 0xFFFF)))
        end.appendLittleEndian(UInt16(min(entryCount, 0xFFFF)))
        end.appendLittleEndian(UInt32(min(centralDirectorySize, Self.zip64Sentinel)))
        end.appendLittleEndian(UInt32(min(centralDirectoryOffset, Self.zip64Sentinel)))
        end.appendLittleEndian(UInt16(0))
        try write(end)

        try handle.synchronize()
    }

    private func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        offset += UInt64(data.count)
    }

    // MARK: - 记录构造

    private static func centralDirectoryRecord(for entry: Entry) -> Data {
        var extra = Data()
        if entry.sizeNeedsZip64 || entry.offsetNeedsZip64 {
            var values = Data()
            if entry.sizeNeedsZip64 {
                values.appendLittleEndian(entry.size)
                values.appendLittleEndian(entry.size)
            }
            if entry.offsetNeedsZip64 {
                values.appendLittleEndian(entry.localHeaderOffset)
            }
            extra.appendLittleEndian(UInt16(0x0001))
            extra.appendLittleEndian(UInt16(values.count))
            extra.append(values)
        }

        var record = Data()
        record.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
        // ZIP64 扩展字段（大小或本地头偏移任一）都要 4.5 的解压器才认，版本号按两者取高。
        let needsZip64 = entry.sizeNeedsZip64 || entry.offsetNeedsZip64
        record.appendLittleEndian(UInt16(45))
        record.appendLittleEndian(UInt16(needsZip64 ? 45 : 20))
        record.appendLittleEndian(UInt16(0x0800))
        record.appendLittleEndian(UInt16(0))
        record.appendLittleEndian(entry.dosTime)
        record.appendLittleEndian(entry.dosDate)
        record.appendLittleEndian(entry.crc32)
        record.appendLittleEndian(UInt32(entry.sizeNeedsZip64 ? zip64Sentinel : entry.size))
        record.appendLittleEndian(UInt32(entry.sizeNeedsZip64 ? zip64Sentinel : entry.size))
        record.appendLittleEndian(UInt16(entry.name.count))
        record.appendLittleEndian(UInt16(extra.count))
        record.appendLittleEndian(UInt16(0))
        record.appendLittleEndian(UInt16(0))
        record.appendLittleEndian(UInt16(0))
        record.appendLittleEndian(UInt32(0))
        record.appendLittleEndian(UInt32(entry.offsetNeedsZip64 ? zip64Sentinel : entry.localHeaderOffset))
        record.append(entry.name)
        record.append(extra)
        return record
    }

    /// 本地头 ZIP64 扩展：同时给出未压缩与压缩后大小（stored 下两者相同）。
    private static func zip64Extra(uncompressedSize: UInt64, compressedSize: UInt64) -> Data {
        var extra = Data()
        extra.appendLittleEndian(UInt16(0x0001))
        extra.appendLittleEndian(UInt16(16))
        extra.appendLittleEndian(uncompressedSize)
        extra.appendLittleEndian(compressedSize)
        return extra
    }

    private static func dosDateTime(_ date: Date) -> (date: UInt16, time: UInt16) {
        // ZIP 的 DOS 时间字段没有时区，解压工具按本地时间解释；
        // 用当前时区取值，解压后看到的时间才与实际一致。
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max(components.year ?? 1980, 1980), 2107)
        let month = min(max(components.month ?? 1, 1), 12)
        let day = min(max(components.day ?? 1, 1), 31)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        let second = min(max(components.second ?? 0, 0), 59)

        let dosDate = UInt16((year - 1980) << 9 | month << 5 | day)
        let dosTime = UInt16(hour << 11 | minute << 5 | second / 2)
        return (UInt16(dosDate), UInt16(dosTime))
    }

    // MARK: - CRC-32

    /// 切片查表（slicing-by-8）：一次处理 8 字节，导出大量页时不会被 CRC 拖慢。
    private static let crcTables: [UInt32] = makeCRCTables()

    private static func makeCRCTables() -> [UInt32] {
        let polynomial: UInt32 = 0xEDB8_8320
        var base = [UInt32](repeating: 0, count: 256)
        for index in 0 ..< 256 {
            var value = UInt32(index)
            for _ in 0 ..< 8 {
                value = (value & 1) == 1 ? polynomial ^ (value >> 1) : value >> 1
            }
            base[index] = value
        }

        var tables = [UInt32](repeating: 0, count: 256 * 8)
        tables.replaceSubrange(0 ..< 256, with: base)
        for slice in 1 ..< 8 {
            for index in 0 ..< 256 {
                let previous = tables[(slice - 1) * 256 + index]
                tables[slice * 256 + index] = (previous >> 8) ^ base[Int(previous & 0xFF)]
            }
        }
        return tables
    }

    static func crc32(_ data: Data) -> UInt32 {
        let tables = crcTables
        var crc: UInt32 = 0xFFFF_FFFF

        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var index = 0
            while index + 8 <= bytes.count {
                let value = UInt32(bytes[index])
                    | UInt32(bytes[index + 1]) << 8
                    | UInt32(bytes[index + 2]) << 16
                    | UInt32(bytes[index + 3]) << 24
                crc ^= value
                crc = tables[7 * 256 + Int(crc & 0xFF)]
                    ^ tables[6 * 256 + Int((crc >> 8) & 0xFF)]
                    ^ tables[5 * 256 + Int((crc >> 16) & 0xFF)]
                    ^ tables[4 * 256 + Int((crc >> 24) & 0xFF)]
                    ^ tables[3 * 256 + Int(bytes[index + 4])]
                    ^ tables[2 * 256 + Int(bytes[index + 5])]
                    ^ tables[1 * 256 + Int(bytes[index + 6])]
                    ^ tables[0 * 256 + Int(bytes[index + 7])]
                index += 8
            }
            while index < bytes.count {
                crc = tables[Int((crc ^ UInt32(bytes[index])) & 0xFF)] ^ (crc >> 8)
                index += 1
            }
        }

        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    mutating func appendLittleEndian(_ value: UInt64) {
        for shift in stride(from: 0, through: 56, by: 8) {
            append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }
}
