import Foundation

/// UCNET framing for control on TCP. Meter packets use a separate UDP subscription.
enum PreSonusWire {
    static let signature: [UInt8] = [0x55, 0x43, 0, 1]
    // A console remembers permissions by installation. Scans and live sessions share the same ID.
    static let clientIdentifier: String = {
        let key = "PreSonus.clientIdentifier"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    static func frame(_ kind: String, source: UInt8 = 0x68, body: [UInt8] = []) -> Data {
        let size = UInt16(body.count + 6)
        var bytes = signature
        bytes += [UInt8(truncatingIfNeeded: size), UInt8(size >> 8)]
        bytes += kind.utf8
        bytes += [source, 0, 0x65, 0]
        bytes += body
        return Data(bytes)
    }

    static func meterRegistration(port: UInt16) -> Data {
        frame("UM", source: 0, body: [UInt8(truncatingIfNeeded: port), UInt8(port >> 8)])
    }

    static func subscribe(id: String) throws -> Data {
        let fields: [String: Any] = [
            "id": "Subscribe", "clientName": "UC-Surface", "clientInternalName": "ucremoteapp",
            "clientType": "iOS", "clientDescription": "Duo Mix", "clientIdentifier": id,
            "clientOptions": "perm users levl redu rtan", "clientEncoding": 23106
        ]
        let json = try JSONSerialization.data(withJSONObject: fields)
        return frame("JM", body: littleEndian(UInt32(json.count)) + json)
    }

    static func parameter(_ field: String, channel: Int, value: Float) -> Data {
        let path = Array("line/ch\(channel)/\(field)".utf8)
        return frame("PV", body: path + [0, 0, 0] + littleEndian(value.bitPattern))
    }

    static func littleEndian(_ number: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: number >> ($0 * 8)) }
    }

    static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
}

/// Each TCP connection gets a fresh decoder. A late packet from an old connection
/// cannot complete a new handshake or insert a stale channel value.
final class PreSonusStream: @unchecked Sendable {
    // A feed can arrive on any queue. Protect the frame and handshake state together.
    private let lock = NSLock()
    private var buffer = [UInt8]()
    private var chunk = [UInt8]()
    private var chunkTotal = 0
    private var acknowledged = false
    private var snapshot: PreSonusSnapshot?
    private var confirmedName: String?
    private var pending = [MixerEvent]()
    private var inputs = Set<Int>()

    var mixerName: String? { lock.withLock { confirmedName } }

    func feed(_ data: Data) throws -> [MixerEvent] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: data)
        var cursor = 0
        var events = [MixerEvent]()
        while buffer.count - cursor >= 6 {
            guard buffer[cursor..<(cursor + 4)].elementsEqual(PreSonusWire.signature) else {
                throw PreSonusError.format
            }
            let size = Int(buffer[cursor + 4]) | Int(buffer[cursor + 5]) << 8
            guard size >= 6 else { throw PreSonusError.format }
            let end = cursor + 6 + size
            if end > buffer.count { break }
            let kind = String(decoding: buffer[(cursor + 6)..<(cursor + 8)], as: UTF8.self)
            let body = Array(buffer[(cursor + 12)..<end])
            try consume(kind, body, events: &events)
            cursor = end
        }
        buffer.removeFirst(cursor)
        return events
    }

    private func consume(_ kind: String, _ body: [UInt8], events: inout [MixerEvent]) throws {
        switch kind {
        case "JM":
            guard body.count >= 4, PreSonusWire.uint32(body, at: 0) == body.count - 4,
                  let fields = try JSONSerialization.jsonObject(with: Data(body.dropFirst(4))) as? [String: Any]
            else { throw PreSonusError.format }
            if fields["id"] as? String == "SubscriptionReply" { acknowledged = true }
        case "ZB":
            guard body.count > 4, PreSonusWire.uint32(body, at: 0) == body.count - 4 else {
                throw PreSonusError.snapshot
            }
            snapshot = try PreSonusSnapshot.read(Array(body.dropFirst(4)))
        case "CK":
            try appendChunk(body)
        case "PV", "PS":
            guard let update = try parameter(kind, body) else { return }
            try record([update], into: &events)
        case "MS":
            try record(faderPositions(body), into: &events)
        default: return
        }
        if acknowledged, let state = snapshot {
            inputs = Set(state.channels.map(\.id))
            confirmedName = state.mixerName
            events.append(.snapshot(state.channels))
            snapshot = nil
            try record(pending, into: &events)
            pending.removeAll()
        }
    }

    private func record(_ updates: [MixerEvent], into events: inout [MixerEvent]) throws {
        if snapshot != nil || chunkTotal != 0 {
            guard pending.count + updates.count <= 4096 else { throw PreSonusError.snapshot }
            pending += updates
            return
        }
        for update in updates {
            switch update {
            case let .level(id, _), let .mute(id, _), let .name(id, _):
                guard inputs.contains(id) else { continue }
            default: continue
            }
            events.append(update)
        }
    }

    // The desk confirms a fader move with a position vector for all strips.
    // Its descriptors identify which slots belong to input channels.
    private func faderPositions(_ body: [UInt8]) throws -> [MixerEvent] {
        guard body.starts(with: "fdrs".utf8) else { return [] }
        guard body.count >= 9 else { throw PreSonusError.format }
        func uint16(at index: Int) -> Int { Int(body[index]) | Int(body[index + 1]) << 8 }
        let slots = uint16(at: 6)
        let groupsAt = 8 + slots * 2
        guard groupsAt < body.count else { throw PreSonusError.format }
        let groups = Int(body[groupsAt])
        guard groupsAt + 1 + groups * 6 == body.count else { throw PreSonusError.format }
        for group in 0..<groups {
            let descriptor = groupsAt + 1 + 6 * group
            guard uint16(at: descriptor) == 0 else { continue } // LINE
            let offset = uint16(at: descriptor + 2)
            let count = uint16(at: descriptor + 4)
            guard offset + count <= slots else { throw PreSonusError.format }
            return (0..<min(count, 32)).map { input in
                let value = Double(uint16(at: 8 + 2 * (offset + input))) / 65_535
                return .level(channel: input + 1, value: value)
            }
        }
        return []
    }

    private func appendChunk(_ body: [UInt8]) throws {
        guard body.count >= 4 else { throw PreSonusError.format }
        guard body[2] == 0x5a && body[3] == 0x42 else { return } // ZB
        guard body.count >= 16 else { throw PreSonusError.snapshot }
        let offset = Int(PreSonusWire.uint32(body, at: 4))
        let total = Int(PreSonusWire.uint32(body, at: 8))
        let count = Int(PreSonusWire.uint32(body, at: 12))
        guard total > 0, total <= PreSonusSnapshot.maximumSize, count > 0,
              offset == chunk.count, count == body.count - 16, offset + count <= total,
              chunkTotal == 0 || total == chunkTotal else { throw PreSonusError.snapshot }
        chunkTotal = total
        chunk += body.dropFirst(16)
        if chunk.count == total {
            snapshot = try PreSonusSnapshot.read(chunk)
            chunk.removeAll()
            chunkTotal = 0
        }
    }

    private func parameter(_ kind: String, _ body: [UInt8]) throws -> MixerEvent? {
        guard let end = body.firstIndex(of: 0) else { throw PreSonusError.format }
        let path = String(decoding: body[..<end], as: UTF8.self).split(separator: "/")
        guard path.count == 3, path[0] == "line", path[1].hasPrefix("ch"),
              let id = Int(path[1].dropFirst(2)), (1...32).contains(id) else { return nil }
        let start = end + 3
        switch (kind, path[2]) {
        case ("PV", "volume"), ("PV", "mute"):
            guard body.count == start + 4 else { throw PreSonusError.format }
            let value = Double(Float(bitPattern: PreSonusWire.uint32(body, at: start)))
            if path[2] == "volume", (0...1).contains(value) { return .level(channel: id, value: value) }
            if path[2] == "mute", value == 0 || value == 1 { return .mute(channel: id, muted: value == 1) }
            throw PreSonusError.format
        case ("PS", "name"), ("PS", "username"):
            guard body.count > start, body.last == 0 else { throw PreSonusError.format }
            let label = String(decoding: body[start..<(body.count - 1)], as: UTF8.self)
            return .name(channel: id, name: label.isEmpty ? "Ch. \(id)" : label)
        default: return nil
        }
    }
}
