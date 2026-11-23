import XCTest
@testable import DuoMix

final class PreSonusProtocolTests: XCTestCase {
    // Independently encoded zlib/UBJSON, with channel 32 named Choir at 75% and muted.
    private let state = Data(base64Encoded: "eJyrzmTKTAnO5A6uzEvOKMrPy6xKzeRIzsjMSSlKzavOZMnJzEutRhFJzjA2qs5kK0vMKU0tBvLzEnNTgzPZnDP0FIyNMjlKi1OLIEKszhn5mUVAlfk5pbmpKfYODAyZLLmlJUBmAwNDLRgAAFJvLHs=")!

    func testSubscriptionNeedsReplyAndSnapshotAndPreservesInterleavedUpdates() throws {
        let stream = PreSonusStream()
        let initial = PreSonusWire.frame("ZB", body: PreSonusWire.littleEndian(UInt32(state.count)) + state)
        for byte in initial {
            XCTAssertTrue(try stream.feed(Data([byte])).isEmpty)
        }

        let label = PreSonusWire.frame("PS", body: Array("line/ch32/username\0\0\0Choir R\0".utf8))
        XCTAssertTrue(try stream.feed(label).isEmpty)
        let reply = Array(#"{"id":"SubscriptionReply"}"#.utf8)
        let events = try stream.feed(PreSonusWire.frame("JM", body: PreSonusWire.littleEndian(UInt32(reply.count)) + reply))
        XCTAssertEqual(events.count, 2)
        guard case let .snapshot(channels) = events.first,
              case let .name(channel, name) = events.last else {
            return XCTFail("Expected synchronized snapshot followed by the console rename.")
        }
        XCTAssertEqual(channels, [MixerChannel(id: 32, name: "Choir", level: 0.75, isMuted: true)])
        XCTAssertEqual(channel, 32)
        XCTAssertEqual(name, "Choir R")
    }

    func testRejectsPartialStateAndInvalidCompression() {
        let noMute = Data(base64Encoded: "eJyrzmTKTAnO5A6uzEvOKMrPy6xKzeRIzsjMSSlKzavOZMnJzEutRhFJzjA2qs5kK0vMKU0tBjHyc0pzU1PsHRgYasEAAP5XHns=")!
        XCTAssertThrowsError(try PreSonusSnapshot.decode(Array(noMute)))
        XCTAssertThrowsError(try PreSonusSnapshot.decode(Array(state.dropLast(4))))
        XCTAssertThrowsError(try PreSonusStream().feed(PreSonusWire.frame("ZB", body: [1, 0, 0, 0] + state)))
    }

    func testGroupedFaderReadbackUsesInputDescriptorAndSkipsSignalMeters() throws {
        let stream = PreSonusStream()
        let reply = Array(#"{"id":"SubscriptionReply"}"#.utf8)
        _ = try stream.feed(PreSonusWire.frame("JM", body: PreSonusWire.littleEndian(UInt32(reply.count)) + reply))
        _ = try stream.feed(PreSonusWire.frame("ZB", body: PreSonusWire.littleEndian(UInt32(state.count)) + state))
        // One unrelated slot precedes the 32 input faders. Only CH32 has synchronized state.
        var slots = [UInt8](repeating: 0, count: 66)
        slots[64] = 0xff
        slots[65] = 0x7f
        let descriptors: [UInt8] = [2, 7, 0, 0, 0, 1, 0, 0, 0, 1, 0, 32, 0]
        let values = [0, 0, 33, 0] as [UInt8]
        let body = values + slots + descriptors
        XCTAssertTrue(try stream.feed(PreSonusWire.frame("MS", body: Array("levl".utf8) + body)).isEmpty)
        let events = try stream.feed(PreSonusWire.frame("MS", body: Array("fdrs".utf8) + body))
        XCTAssertEqual(events.count, 1)
        guard case let .level(id, value) = events.first else { return XCTFail("Expected channel readback.") }
        XCTAssertEqual(id, 32)
        XCTAssertEqual(value, 32767.0 / 65535, accuracy: 0.000001)
    }

    func testRejectsOutOfOrderSnapshotChunk() {
        let header: [UInt8] = [0, 0, 0x5a, 0x42, 2, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0]
        XCTAssertThrowsError(try PreSonusStream().feed(PreSonusWire.frame("CK", body: header + [42])))
    }

    func testWritesLittleEndianFloatAndOneBasedChannel() {
        let expected = Data([0x55, 0x43, 0x00, 0x01, 0x1b, 0x00, 0x50, 0x56, 0x68, 0, 0x65, 0])
            + Data("line/ch32/mute".utf8) + Data([0, 0, 0, 0, 0, 0x80, 0x3f])
        XCTAssertEqual(PreSonusWire.parameter("mute", channel: 32, value: 1), expected)
    }
}
