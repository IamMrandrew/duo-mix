import XCTest
@testable import DuoMix

final class MixerScanNetworkTests: XCTestCase {
    func testSmallSubnetExcludesOwnAddressesAndSubnetBoundaries() throws {
        // 192.168.8.133/29, with a second local address at .130.
        let plan = try XCTUnwrap(MixerScanAddressPlan(ip: 0xc0a80885, netmask: 0xfffffff8,
                                                      ownIPs: [0xc0a80882]))
        XCTAssertEqual(plan.hosts, ["192.168.8.129", "192.168.8.131", "192.168.8.132", "192.168.8.134"])
        XCTAssertFalse(plan.isPartial)
    }

    func testLargeNetworkScansOneLocalSliceAndPreservesRealSubnetEndpoints() throws {
        let full = try XCTUnwrap(MixerScanAddressPlan(ip: 0xc0a80805, netmask: 0xffffff00))
        XCTAssertEqual(full.hosts.count, 253)
        XCTAssertEqual(full.hosts.first, "192.168.8.1")
        XCTAssertEqual(full.hosts.last, "192.168.8.254")
        XCTAssertFalse(full.isPartial)

        let partial = try XCTUnwrap(MixerScanAddressPlan(ip: 0xc0a80805, netmask: 0xffff0000))
        XCTAssertEqual(partial.hosts.count, 255)
        XCTAssertEqual(partial.hosts.first, "192.168.8.0")
        XCTAssertEqual(partial.hosts.last, "192.168.8.255")
        XCTAssertTrue(partial.isPartial)
    }

    func testPointToPointAndSingleAddressLinks() throws {
        let link = try XCTUnwrap(MixerScanAddressPlan(ip: 0xc0a80880, netmask: 0xfffffffe))
        XCTAssertEqual(link.hosts, ["192.168.8.129"])
        let localOnly = try XCTUnwrap(MixerScanAddressPlan(ip: 0xc0a80880, netmask: .max))
        XCTAssertTrue(localOnly.hosts.isEmpty)
    }

    func testInvalidNetworksDoNotCreateCandidates() {
        XCTAssertNil(MixerScanAddressPlan(ip: 0xc0a80805, netmask: 0xff00ffff))
        XCTAssertNil(MixerScanAddressPlan(ip: 0xc0a80805, netmask: 0))
        for invalidIP: UInt32 in [0, 0x7f000001, 0xe0000001, 0xffffffff, 0xc0a80800, 0xc0a808ff] {
            XCTAssertNil(MixerScanAddressPlan(ip: invalidIP, netmask: 0xffffff00))
        }
    }
}
