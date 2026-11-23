import Network
import XCTest

// A peer built from the published Series III wire format. It uses no production codec.
// https://featherbear.cc/presonus-studiolive-api/#research
enum DeskWire {
    static func listener() throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        return try NWListener(using: parameters)
    }

    static func sendInitialState(to peer: NWConnection) {
        let reply = Data(#"{"id":"SubscriptionReply"}"#.utf8)
        // Python zlib.compress of UBJSON Synchronize, children.line.children.ch1.values
        // containing name/username "Kick", Float32 volume 0.5 and Float32 mute 0.
        let state = Data(base64Encoded: "eJxNikEKgCAUBaVEgk7TCTpAS08Q+sFH+gVNoaS7F62c1TBMwwCrMeuLjUuRcRMm4+BtIm6QHkytL6NxS4Oquy+Uv4H3QBpygzkwlUypD6pGXwLZVQgBGcpJ9jPx/LzD7Cr1")!
        func withLength(_ content: Data) -> Data {
            precondition(content.count < 256)
            return Data([UInt8(content.count), 0, 0, 0]) + content
        }
        // The published 16R trace sends the chunked state before SubscriptionReply.
        func chunk(_ part: Range<Int>) -> Data {
            let header = Data([0, 0, 0x5a, 0x42, UInt8(part.lowerBound), 0, 0, 0,
                               UInt8(state.count), 0, 0, 0, UInt8(part.count), 0, 0, 0])
            return frame("CK", header + state[part])
        }
        let frames = chunk(0..<40) + chunk(40..<state.count) + frame("JM", withLength(reply))
            + frame("PV", Data("line/ch1/volume".utf8) + [0, 0, 0, 0, 0, 0x80, 0x3e])
            + frame("PV", Data("line/ch1/mute".utf8) + [0, 0, 0, 0, 0, 0x80, 0x3f])
        peer.send(content: frames.prefix(3), completion: .contentProcessed { error in
            if let error { XCTFail("Sending desk header failed: \(error)") }
        })
        peer.send(content: frames.dropFirst(3), completion: .contentProcessed { error in
            if let error { XCTFail("Sending desk state failed: \(error)") }
        })
    }

    static func frame(_ type: String, _ content: Data) -> Data {
        let payload = Data(type.utf8) + [0x65, 0, 0x6a, 0] + content
        precondition(payload.count < 256)
        return Data([0x55, 0x43, 0, 1, UInt8(payload.count), 0]) + payload
    }

    static func receive(from peer: NWConnection, onClose: (() -> Void)? = nil,
                        process: @escaping (String, Data) throws -> Bool) {
        peer.receive(minimumIncompleteLength: 6, maximumLength: 6) { header, _, ended, error in
            if (header?.isEmpty ?? true), (ended || error != nil), let onClose {
                onClose()
                return
            }
            guard let header, header.count == 6, error == nil else {
                XCTFail("Disconnected before the desk received all changes")
                return
            }
            XCTAssertEqual(Array(header.prefix(4)), [0x55, 0x43, 0, 1])
            let count = Int(header[4]) + Int(header[5]) * 256
            guard count >= 6 else { return XCTFail("Invalid UCNET header size") }
            peer.receive(minimumIncompleteLength: count, maximumLength: count) { payload, _, _, error in
                guard let payload, payload.count == count, error == nil else {
                    return XCTFail("Incomplete packet from driver")
                }
                do {
                    let type = String(decoding: payload.prefix(2), as: UTF8.self)
                    if try process(type, Data(payload.dropFirst(6))) {
                        receive(from: peer, onClose: onClose, process: process)
                    }
                } catch {
                    XCTFail("Could not read driver packet: \(error)")
                }
            }
        }
    }
}
