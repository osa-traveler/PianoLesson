import Compression
import Foundation

/// .mxl を読むための最小限の ZIP 読み込み（無圧縮と deflate のみ）。
public struct ZipArchive: Sendable {
    public struct Entry: Sendable {
        public var path: String
        var method: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    public enum ZipError: Error {
        case notZip, unsupportedMethod(UInt16), corrupted, missing(String)
    }

    private let data: Data
    public let entries: [Entry]

    public init(data: Data) throws {
        self.data = data
        // 末尾の End of Central Directory を探す
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipError.notZip }
        var eocd = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while i >= lowest {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }
        let count = Int(Self.u16(bytes, eocd + 10))
        var p = Int(Self.u32(bytes, eocd + 16))
        var list: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= bytes.count, Self.u32(bytes, p) == 0x0201_4B50 else { throw ZipError.corrupted }
            let method = Self.u16(bytes, p + 10)
            let compressed = Int(Self.u32(bytes, p + 20))
            let uncompressed = Int(Self.u32(bytes, p + 24))
            let nameLength = Int(Self.u16(bytes, p + 28))
            let extraLength = Int(Self.u16(bytes, p + 30))
            let commentLength = Int(Self.u16(bytes, p + 32))
            let offset = Int(Self.u32(bytes, p + 42))
            guard p + 46 + nameLength <= bytes.count else { throw ZipError.corrupted }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            list.append(Entry(path: name, method: method, compressedSize: compressed,
                              uncompressedSize: uncompressed, localHeaderOffset: offset))
            p += 46 + nameLength + extraLength + commentLength
        }
        entries = list
    }

    public func contents(of path: String) throws -> Data {
        guard let entry = entries.first(where: { $0.path == path }) else { throw ZipError.missing(path) }
        let bytes = [UInt8](data)
        let h = entry.localHeaderOffset
        guard h + 30 <= bytes.count, Self.u32(bytes, h) == 0x0403_4B50 else { throw ZipError.corrupted }
        let start = h + 30 + Int(Self.u16(bytes, h + 26)) + Int(Self.u16(bytes, h + 28))
        guard start + entry.compressedSize <= bytes.count else { throw ZipError.corrupted }
        let raw = Data(bytes[start..<(start + entry.compressedSize)])
        switch entry.method {
        case 0: return raw
        case 8: return try Self.inflate(raw, size: entry.uncompressedSize)
        default: throw ZipError.unsupportedMethod(entry.method)
        }
    }

    private static func inflate(_ input: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                // COMPRESSION_ZLIB は raw deflate（ZIP と同じ形式）
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.corrupted }
        return output
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}
