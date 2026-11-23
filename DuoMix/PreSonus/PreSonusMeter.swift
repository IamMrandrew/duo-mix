import Foundation

enum PreSonusMeter {
    /// Group zero in a UDP MS/levl message is the input signal, ahead of the strip.
    /// Each six-byte descriptor locates one group within a shared UInt16 vector.
    static func inputLevels(_ datagram: Data) -> [Int: Double]? {
        guard (21...65_535).contains(datagram.count) else { return nil }
        let bytes = [UInt8](datagram)
        guard bytes.starts(with: PreSonusWire.signature),
              bytes[6..<8].elementsEqual("MS".utf8),
              bytes[12..<16].elementsEqual("levl".utf8) else { return nil }

        func uint16(_ index: Int) -> Int {
            Int(bytes[index]) | Int(bytes[index + 1]) << 8
        }
        // Bytes 4–5 carry the desk's source port in UDP; they are not a TCP frame size.
        let slots = uint16(18)
        let groupsAt = 20 + slots * 2
        guard groupsAt < bytes.count else { return nil }
        let groups = Int(bytes[groupsAt])
        guard groupsAt + 1 + groups * 6 == bytes.count else { return nil }
        var inputs: Range<Int>?
        for group in 0..<groups {
            let descriptor = groupsAt + 1 + group * 6
            let offset = uint16(descriptor + 2)
            let count = uint16(descriptor + 4)
            guard offset + count <= slots else { return nil }
            if bytes[descriptor] == 0 && bytes[descriptor + 1] == 0 {
                guard inputs == nil, count > 0 else { return nil }
                inputs = offset..<(offset + min(count, 32))
            }
        }
        guard let inputs else { return nil }
        var levels = [Int: Double](minimumCapacity: inputs.count)
        for (index, slot) in inputs.enumerated() {
            let raw = uint16(20 + slot * 2)
            // The 32SC community implementation models this as linear amplitude.
            // Until checked against a 32SX test tone, report this as estimated dBFS.
            levels[index + 1] = raw == 0 ? -.infinity : 20 * log10(Double(raw) / 65_535)
        }
        return levels
    }
}
