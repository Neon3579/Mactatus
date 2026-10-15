import Testing
@testable import MetricsKit

@Suite("CPU 계산")
struct CPUMathTests {
    @Test func usageFromTickDifference() throws {
        let before = [CoreTicks(user: 100, system: 50, idle: 850, nice: 0),
                      CoreTicks(user: 0, system: 0, idle: 1000, nice: 0)]
        let after = [CoreTicks(user: 160, system: 70, idle: 870, nice: 0),   // 80/100 사용
                     CoreTicks(user: 10, system: 0, idle: 1090, nice: 0)]    // 10/100 사용
        let reading = try #require(CPUMath.reading(previous: before, current: after, efficiencyCores: 1))
        #expect(reading.cores.map(\.usage) == [0.8, 0.1])
        #expect(reading.cores.map(\.kind) == [.efficiency, .performance])
        #expect(abs(reading.total - 0.45) < 1e-9)
        #expect(abs(reading.user - 0.35) < 1e-9)
        #expect(abs(reading.system - 0.10) < 1e-9)
    }

    @Test func counterWrapAround() throws {
        let before = [CoreTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)]
        let after = [CoreTicks(user: 10, system: 0, idle: 20, nice: 0)]   // user +20, idle +20
        let reading = try #require(CPUMath.reading(previous: before, current: after, efficiencyCores: 0))
        #expect(reading.total == 0.5)
        #expect(reading.cores[0].kind == .unknown)
    }

    @Test func mismatchedCoreCountIsIgnored() {
        #expect(CPUMath.reading(previous: [], current: [CoreTicks(user: 1, system: 1, idle: 1, nice: 0)], efficiencyCores: 0) == nil)
    }
}

@Suite("표시 형식")
struct MetricsFormatTests {
    @Test func memory() {
        #expect(MetricsFormat.memory(8_589_934_592) == "8.0 GB")
        #expect(MetricsFormat.memory(536_870_912) == "512 MB")
    }

    @Test func storageAndRates() {
        #expect(MetricsFormat.storage(245_000_000_000) == "245 GB")
        #expect(MetricsFormat.storage(1_200_000_000_000) == "1.2 TB")
        #expect(MetricsFormat.rate(1_234_567) == "1.2 MB/s")
        #expect(MetricsFormat.rate(340_000) == "340 KB/s")
        #expect(MetricsFormat.rate(0) == "0 KB/s")
    }

    @Test func durations() {
        #expect(MetricsFormat.duration(minutes: 174) == "2시간 54분")
        #expect(MetricsFormat.duration(minutes: 45) == "45분")
        #expect(MetricsFormat.duration(minutes: 120) == "2시간")
    }
}

@Suite("실제 측정(이 맥)")
struct LiveSamplerTests {
    @Test func samplersReturnPlausibleValues() async throws {
        let monitor = SystemMonitor()
        _ = await monitor.sample(detailed: true, processLimit: 5)
        try await Task.sleep(for: .milliseconds(500))
        let snapshot = await monitor.sample(detailed: true, processLimit: 5)
        let cpu = try #require(snapshot.cpu)
        #expect((0...1).contains(cpu.total))
        #expect(cpu.cores.count == Int(Sysctl.value("hw.ncpu", as: Int32.self, default: 0)))
        let memory = try #require(snapshot.memory)
        #expect(memory.total > 0 && memory.used <= memory.total)
        #expect(snapshot.disk.map { $0.total > 0 } ?? false)
    }
}
