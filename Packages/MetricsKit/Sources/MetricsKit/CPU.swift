import Darwin
import Foundation

/// 코어별 틱(user, system, idle, nice).
struct CoreTicks: Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

/// 두 번 읽은 틱의 차이로 사용률을 계산한다(32비트 카운터가 넘쳐도 맞게 &- 사용).
enum CPUMath {
    static func reading(previous: [CoreTicks], current: [CoreTicks], efficiencyCores: Int) -> CPUReading? {
        guard previous.count == current.count, !current.isEmpty else { return nil }
        var cores: [CoreReading] = []
        var sumUser = 0.0, sumSystem = 0.0, sumTotal = 0.0
        for (i, (a, b)) in zip(previous, current).enumerated() {
            let user = Double(b.user &- a.user) + Double(b.nice &- a.nice)
            let system = Double(b.system &- a.system)
            let idle = Double(b.idle &- a.idle)
            let total = user + system + idle
            let usage = total > 0 ? (user + system) / total : 0
            let kind: CoreKind = efficiencyCores > 0 ? (i < efficiencyCores ? .efficiency : .performance) : .unknown
            cores.append(CoreReading(index: i, kind: kind, usage: usage))
            sumUser += user; sumSystem += system; sumTotal += total
        }
        guard sumTotal > 0 else { return nil }
        return CPUReading(total: (sumUser + sumSystem) / sumTotal, user: sumUser / sumTotal,
                          system: sumSystem / sumTotal, cores: cores)
    }
}

final class CPUSampler {
    private let host = mach_host_self()
    private var previous: [CoreTicks]?
    /// Apple Silicon은 효율 코어가 앞 번호(cpu0…)에 온다.
    private let efficiencyCores: Int = {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.perflevel1.logicalcpu", &count, &size, nil, 0) == 0 else { return 0 }
        var name = [CChar](repeating: 0, count: 32)
        var nameSize = name.count
        sysctlbyname("hw.perflevel1.name", &name, &nameSize, nil, 0)
        let label = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return label == "Efficiency" ? Int(count) : 0
    }()

    func sample() -> CPUReading? {
        guard let current = readTicks() else { return nil }
        defer { previous = current }
        guard let previous else { return nil }
        return CPUMath.reading(previous: previous, current: current, efficiencyCores: efficiencyCores)
    }

    private func readTicks() -> [CoreTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        return (0..<Int(cpuCount)).map { i in
            let base = Int(CPU_STATE_MAX) * i
            return CoreTicks(user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                             system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                             idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                             nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
    }
}

/// CPU를 많이 쓰는 프로세스. 다른 사용자(root 등)의 프로세스는 권한이 없어 빠진다.
final class ProcessSampler {
    private var previous: [pid_t: UInt64] = [:]
    private var previousTime: UInt64 = 0
    private var names: [pid_t: (name: String, path: String?)] = [:]
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    func sample(limit: Int) -> [ProcessReading] {
        let now = mach_absolute_time()
        var current: [pid_t: UInt64] = [:]
        for pid in Self.allPIDs() where pid > 0 {
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard result == 0 else { continue }
            current[pid] = info.ri_user_time &+ info.ri_system_time
        }
        defer {
            previous = current
            previousTime = now
        }
        guard previousTime > 0 else { return [] }
        // rusage 시간은 mach 시간 단위 → ns로 바꾼다
        let elapsed = Double(now - previousTime)
        guard elapsed > 0 else { return [] }
        let top = current.compactMap { pid, time -> (pid_t, Double)? in
            guard let before = previous[pid], time >= before else { return nil }
            return (pid, Double(time - before) / elapsed * 100)
        }
        .filter { $0.1 >= 0.1 }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)

        names = names.filter { current[$0.key] != nil }
        return top.map { pid, percent in
            let label = names[pid] ?? Self.describe(pid)
            names[pid] = label
            return ProcessReading(pid: pid, name: label.name, cpuPercent: percent, appPath: label.path)
        }
    }

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.stride))
        }
        return Array(pids.prefix(Int(max(count, 0))))
    }

    /// 앱이면 앱 이름과 경로(아이콘용), 아니면 실행 파일 이름.
    private static func describe(_ pid: pid_t) -> (String, String?) {
        if let app = NSRunningApplicationLookup.app(pid: pid) { return app }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            // …/Foo.app/Contents/MacOS/Foo → 앱 경로
            if let range = path.range(of: ".app/Contents/", options: .backwards) {
                let appPath = String(path[..<range.lowerBound]) + ".app"
                return ((path as NSString).lastPathComponent, appPath)
            }
            return ((path as NSString).lastPathComponent, nil)
        }
        return ("pid \(pid)", nil)
    }
}
