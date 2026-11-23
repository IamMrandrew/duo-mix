import Foundation
import zlib

enum PreSonusError: LocalizedError {
    case format, snapshot, unsupported

    var errorDescription: String? {
        switch self {
        case .format: return "The console sent an unreadable UCNET message."
        case .snapshot: return "The console sent an incomplete channel state. Check its firmware and reconnect."
        case .unsupported: return "The console uses an unsupported state format."
        }
    }
}

/// The console sends a zlib stream containing a UBJSON parameter tree.
enum PreSonusSnapshot {
    static let maximumSize = 8 * 1024 * 1024

    static func decode(_ compressed: [UInt8]) throws -> [MixerChannel] {
        guard !compressed.isEmpty, compressed.count <= maximumSize else { throw PreSonusError.snapshot }
        var capacity = 256 * 1024
        while capacity <= maximumSize {
            var output = [UInt8](repeating: 0, count: capacity)
            var size = uLongf(capacity)
            let status = uncompress(&output, &size, compressed, uLong(compressed.count))
            if status == Z_OK {
                output.removeSubrange(Int(size)..<output.count)
                var reader = UBJSON(bytes: output)
                let tree = try reader.value()
                guard reader.isAtEnd, tree["id"]?.string == "Synchronize",
                      let inputs = tree["children"]?["line"]?["children"]?.object else {
                    throw PreSonusError.snapshot
                }
                return try channels(in: inputs)
            }
            guard status == Z_BUF_ERROR else { throw PreSonusError.snapshot }
            capacity *= 2
        }
        throw PreSonusError.snapshot
    }

    private static func channels(in inputs: [String: UBValue]) throws -> [MixerChannel] {
        var result = [MixerChannel]()
        for id in 1...32 {
            guard let input = inputs["ch\(id)"] else { continue }
            guard let fields = input["values"],
                  let level = fields["volume"]?.number, (0...1).contains(level),
                  let mute = fields["mute"]?.number, mute == 0 || mute == 1 else {
                throw PreSonusError.snapshot
            }
            let label = [fields["username"]?.string, fields["name"]?.string]
                .compactMap { $0 }.first { !$0.isEmpty } ?? "Ch. \(id)"
            result.append(MixerChannel(id: id, name: label, level: level, isMuted: mute == 1))
        }
        guard !result.isEmpty else { throw PreSonusError.snapshot }
        return result
    }
}

private enum UBValue {
    case dictionary([String: UBValue]), numberValue(Double), text(String), other

    var object: [String: UBValue]? {
        if case .dictionary(let object) = self { return object }
        return nil
    }

    subscript(key: String) -> UBValue? { object?[key] }

    var string: String? {
        if case .text(let string) = self { return string }
        return nil
    }

    var number: Double? {
        if case .numberValue(let number) = self { return number }
        return nil
    }
}

// Only objects, text, and numbers need storage. Arrays contain parameter metadata.
private struct UBJSON {
    let bytes: [UInt8]
    private(set) var cursor = 0
    private var nodes = 0
    var isAtEnd: Bool { cursor == bytes.count }

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func value(depth: Int = 0) throws -> UBValue {
        guard depth < 64, nodes < 500_000 else { throw PreSonusError.snapshot }
        nodes += 1
        let tag = try next()
        switch tag {
        case 123: // {
            var fields = [String: UBValue]()
            while try peek() != 125 {
                let key = try text()
                fields[key] = try value(depth: depth + 1)
            }
            cursor += 1
            return .dictionary(fields)
        case 91: // [
            while try peek() != 93 { _ = try value(depth: depth + 1) }
            cursor += 1
            return .other
        case 83, 72: return .text(try text()) // S, H
        case 67: return .text(String(decoding: [try next()], as: UTF8.self)) // C
        case 100: return .numberValue(Double(Float(bitPattern: UInt32(try unsigned(4))))) // d
        case 68: return .numberValue(Double(bitPattern: try unsigned(8))) // D
        case 84: return .numberValue(1) // T
        case 70: return .numberValue(0) // F
        case 90: return .other // Z
        default: return .numberValue(Double(try integer(tag)))
        }
    }

    private mutating func text() throws -> String {
        let tag = try next()
        let length = try integer(tag)
        guard length >= 0, length <= Int64(bytes.count - cursor) else { throw PreSonusError.snapshot }
        let end = cursor + Int(length)
        defer { cursor = end }
        return String(decoding: bytes[cursor..<end], as: UTF8.self)
    }

    private mutating func integer(_ tag: UInt8) throws -> Int64 {
        switch tag {
        case 105: return Int64(Int8(bitPattern: try next()))
        case 85: return Int64(try next())
        case 73: return Int64(Int16(bitPattern: UInt16(try unsigned(2))))
        case 108: return Int64(Int32(bitPattern: UInt32(try unsigned(4))))
        case 76: return Int64(bitPattern: try unsigned(8))
        default: throw PreSonusError.unsupported
        }
    }

    private mutating func unsigned(_ count: Int) throws -> UInt64 {
        guard bytes.count - cursor >= count else { throw PreSonusError.snapshot }
        let end = cursor + count
        defer { cursor = end }
        return bytes[cursor..<end].reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private func peek() throws -> UInt8 {
        guard cursor < bytes.count else { throw PreSonusError.snapshot }
        return bytes[cursor]
    }

    private mutating func next() throws -> UInt8 {
        let byte = try peek()
        cursor += 1
        return byte
    }
}
