import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps
import SystemConfiguration

// MARK: - 앱 이름 찾기

enum NSRunningApplicationLookup {
    static func app(pid: pid_t) -> (String, String?)? {
        guard let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName else { return nil }
        return (name, app.bundleURL?.path)
    }
}

// MARK: - sysctl

enum Sysctl {
    static func value<T: BitwiseCopyable>(_ name: String, as: T.Type, default fallback: T) -> T {
        var value = fallback
        var size = MemoryLayout<T>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : fallback
    }
}

// MARK: - 메모리

final class MemorySampler {
    private let host = mach_host_self()
    private let total = Sysctl.value("hw.memsize", as: UInt64.self, default: 0)

    func sample() -> MemoryReading? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let app = UInt64(stats.internal_page_count &- stats.purgeable_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let cached = UInt64(stats.external_page_count &+ stats.purgeable_count) * page

        let swap = Sysctl.value("vm.swapusage", as: xsw_usage.self, default: xsw_usage())
        let pressure: MemoryPressure = switch Sysctl.value("kern.memorystatus_vm_pressure_level", as: Int32.self, default: 1) {
        case 4...: .critical
        case 2...: .warning
        default: .normal
        }
        return MemoryReading(total: total, used: min(app + wired + compressed, total), app: app, wired: wired,
                             compressed: compressed, cached: cached, swapUsed: swap.xsu_used, swapTotal: swap.xsu_total,
                             pressure: pressure)
    }
}

// MARK: - IOKit 도우미

enum IORegistry {
    /// 클래스 이름이 같은 모든 서비스에서 property 하나씩.
    static func property(class className: String, key: String) -> [Any] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var values: [Any] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                values.append(value)
            }
            IOObjectRelease(service)
        }
        return values
    }

    static func properties(name: String) -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching(name))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return props?.takeRetainedValue() as? [String: Any]
    }
}

// MARK: - GPU

enum GPUReader {
    /// Apple Silicon: IOAccelerator의 "Device Utilization %"(0~1).
    static func utilization() -> Double? {
        let values = IORegistry.property(class: "IOAccelerator", key: "PerformanceStatistics")
            .compactMap { ($0 as? [String: Any])?["Device Utilization %"] as? Int }
        return values.max().map { Double($0) / 100 }
    }
}

// MARK: - 디스크

final class DiskSampler {
    private var previous: (read: UInt64, write: UInt64, time: Date)?
    private var volume: (name: String, total: Int64, available: Int64, time: Date)?

    func sample() -> DiskReading? {
        let now = Date()
        // 남은 용량(정리 가능한 캐시 포함)은 계산이 무거워서 2분마다만 다시 읽는다
        if volume == nil || now.timeIntervalSince(volume!.time) > 120 {
            let url = URL(fileURLWithPath: "/")
            if let values = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
                volume = (values.volumeLocalizedName ?? "Macintosh HD", Int64(values.volumeTotalCapacity ?? 0),
                          values.volumeAvailableCapacityForImportantUsage ?? 0, now)
            }
        }
        var read: UInt64 = 0, write: UInt64 = 0
        for stats in IORegistry.property(class: "IOBlockStorageDriver", key: "Statistics") {
            guard let dict = stats as? [String: Any] else { continue }
            read += (dict["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write += (dict["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        defer { previous = (read, write, now) }
        guard let volume else { return nil }
        var readRate = 0.0, writeRate = 0.0
        if let previous, now > previous.time {
            let seconds = now.timeIntervalSince(previous.time)
            readRate = Double(read &- previous.read) / seconds
            writeRate = Double(write &- previous.write) / seconds
            if read < previous.read { readRate = 0 }
            if write < previous.write { writeRate = 0 }
        }
        return DiskReading(volumeName: volume.name, total: volume.total, available: volume.available,
                           readRate: readRate, writeRate: writeRate)
    }
}

// MARK: - 네트워크

final class NetworkSampler {
    private var previous: (down: UInt64, up: UInt64, time: Date)?
    private var interfaceInfo: (name: String?, display: String?, address: String?, time: Date)?
    /// 인터페이스 번호 → 이름. if_indextoname은 부를 때마다 전체 목록을 다시 만들어 비싸므로 캐시한다.
    private var names: [UInt16: String] = [:]
    private var namesUpdated = Date.distantPast

    func sample() -> NetworkReading? {
        let now = Date()
        if now.timeIntervalSince(namesUpdated) > 60 {
            names = Self.interfaceNames()
            namesUpdated = now
        }
        let (down, up) = Self.totals(names: names)
        defer { previous = (down, up, now) }
        if interfaceInfo == nil || now.timeIntervalSince(interfaceInfo!.time) > 15 {
            let name = Self.primaryInterface()
            interfaceInfo = (name, name.flatMap(Self.displayName), name.flatMap(Self.ipv4Address), now)
        }
        var downRate = 0.0, upRate = 0.0
        if let previous, now > previous.time, down >= previous.down, up >= previous.up {
            let seconds = now.timeIntervalSince(previous.time)
            downRate = Double(down - previous.down) / seconds
            upRate = Double(up - previous.up) / seconds
        }
        return NetworkReading(downRate: downRate, upRate: upRate, interfaceName: interfaceInfo?.name,
                              interfaceDisplayName: interfaceInfo?.display, address: interfaceInfo?.address)
    }

    static func interfaceNames() -> [UInt16: String] {
        guard let list = if_nameindex() else { return [:] }
        defer { if_freenameindex(list) }
        var result: [UInt16: String] = [:]
        var entry = list
        while entry.pointee.if_index != 0, let name = entry.pointee.if_name {
            result[UInt16(entry.pointee.if_index)] = String(cString: name)
            entry += 1
        }
        return result
    }

    /// en* 인터페이스(Wi-Fi·이더넷)의 64비트 누적 바이트. VPN(utun)은 중복이라 뺀다.
    static func totals(names: [UInt16: String]) -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return (0, 0) }
        var down: UInt64 = 0, up: UInt64 = 0
        var offset = 0
        buffer.withUnsafeBytes { raw in
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.load(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2 {
                    let message = raw.load(fromByteOffset: offset, as: if_msghdr2.self)
                    if names[message.ifm_index]?.hasPrefix("en") == true {
                        down += message.ifm_data.ifi_ibytes
                        up += message.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (down, up)
    }

    static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Mactatus" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return nil }
        return global["PrimaryInterface"] as? String
    }

    static func displayName(for bsdName: String) -> String? {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        guard let match = interfaces.first(where: { SCNetworkInterfaceGetBSDName($0) as String? == bsdName }) else { return nil }
        return SCNetworkInterfaceGetLocalizedDisplayName(match) as String?
    }

    static func ipv4Address(for bsdName: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = entry.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ifa.ifa_name) == bsdName else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        return nil
    }
}

// MARK: - 배터리

enum BatteryReader {
    static func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { return nil }

        let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
        let onAC = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        let toEmpty = desc[kIOPSTimeToEmptyKey] as? Int
        let toFull = desc[kIOPSTimeToFullChargeKey] as? Int

        var reading = BatteryReading(
            percent: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current,
            isCharging: charging, onAC: onAC,
            minutesRemaining: (!onAC && (toEmpty ?? -1) > 0) ? toEmpty : nil,
            minutesToFull: (charging && (toFull ?? -1) > 0) ? toFull : nil)

        if let top = IORegistry.properties(name: "AppleSmartBattery") {
            // Apple Silicon은 일부 값을 BatteryData 안에 둔다
            let nested = top["BatteryData"] as? [String: Any] ?? [:]
            let smart = nested.merging(top) { _, topLevel in topLevel }
            reading.cycleCount = smart["CycleCount"] as? Int
            if let design = smart["DesignCapacity"] as? Int, design > 0,
               let full = (smart["NominalChargeCapacity"] as? Int) ?? (smart["AppleRawMaxCapacity"] as? Int) {
                reading.health = Double(full) / Double(design)
            }
            if let millivolts = (smart["Voltage"] as? NSNumber)?.int64Value,
               let milliamps = ((smart["InstantAmperage"] ?? smart["Amperage"]) as? NSNumber)?.int64Value {
                reading.watts = Double(millivolts) / 1000 * Double(milliamps) / 1000
            }
            if let adapter = smart["AdapterDetails"] as? [String: Any], let watts = adapter["Watts"] as? Int, watts > 0, onAC {
                reading.adapterWatts = watts
            }
            if let temp = smart["Temperature"] as? Int { reading.temperature = Double(temp) / 100 }
        }
        return reading
    }
}
