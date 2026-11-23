import Darwin
import Foundation
import Network

struct MixerScanNetwork: Sendable {
    let interface: NWInterface
    let hosts: [String]
    let isPartial: Bool

    static func current() async throws -> MixerScanNetwork {
        try Task.checkCancellation()
        let monitor = NWPathMonitor(prohibitedInterfaceTypes: [.cellular, .loopback, .other])
        let queue = DispatchQueue(label: "DuoMix.discovery.path")
        let (updates, continuation) = AsyncStream<NWPath>.makeStream(bufferingPolicy: .bufferingNewest(1))
        monitor.pathUpdateHandler = { path in
            continuation.yield(path)
            continuation.finish()
        }
        monitor.start(queue: queue)
        defer { monitor.cancel() }
        queue.asyncAfter(deadline: .now() + 2) { continuation.finish() }

        var iterator = updates.makeAsyncIterator()
        let first = await iterator.next()
        try Task.checkCancellation()
        guard let path = first, path.status == .satisfied else { throw StudioLiveScanError.noNetwork }
        let addresses = localAddresses()
        let ownIPs = Set(addresses.map(\.ip))
        for interface in path.availableInterfaces where interface.type == .wifi || interface.type == .wiredEthernet {
            guard path.usesInterfaceType(interface.type) else { continue }
            for address in addresses where address.name == interface.name {
                guard let plan = MixerScanAddressPlan(ip: address.ip, netmask: address.mask, ownIPs: ownIPs),
                      !plan.hosts.isEmpty else { continue }
                return Self(interface: interface, hosts: plan.hosts, isPartial: plan.isPartial)
            }
        }
        throw StudioLiveScanError.noNetwork
    }

    private static func localAddresses() -> [(name: String, ip: UInt32, mask: UInt32)] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let list else { return [] }
        defer { freeifaddrs(list) }
        var addresses: [(String, UInt32, UInt32)] = []
        var entry: UnsafeMutablePointer<ifaddrs>? = list
        while let current = entry {
            let item = current.pointee
            entry = item.ifa_next
            guard let address = item.ifa_addr, let mask = item.ifa_netmask,
                  address.pointee.sa_family == AF_INET, item.ifa_flags & UInt32(IFF_UP) != 0,
                  item.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            func number(_ value: UnsafePointer<sockaddr>) -> UInt32 {
                value.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr.bigEndian }
            }
            addresses.append((String(cString: item.ifa_name), number(address), number(mask)))
        }
        return addresses
    }
}

/// Addresses are host-order UInt32 values, with the first IPv4 octet in the high byte.
struct MixerScanAddressPlan {
    let hosts: [String]
    let isPartial: Bool

    init?(ip: UInt32, netmask: UInt32, ownIPs: Set<UInt32> = []) {
        let hostBits = ~netmask
        let firstOctet = ip >> 24
        guard netmask != 0, hostBits & (hostBits &+ 1) == 0,
              firstOctet != 0, firstOctet != 127, firstOctet < 224 else { return nil }
        let network = ip & netmask
        let broadcast = network | hostBits
        // A /31 has two peer addresses. A /32 has no peer to discover.
        guard hostBits <= 1 || (ip != network && ip != broadcast) else { return nil }
        let start = max(network, ip & 0xffffff00)
        let end = min(broadcast, ip | 0xff)
        var hosts: [String] = []
        for candidate in start...end {
            guard candidate != ip, !ownIPs.contains(candidate) else { continue }
            if hostBits > 1 && (candidate == network || candidate == broadcast) { continue }
            hosts.append("\(candidate >> 24).\((candidate >> 16) & 255).\((candidate >> 8) & 255).\(candidate & 255)")
        }
        self.hosts = hosts
        isPartial = hostBits > 255
    }
}
