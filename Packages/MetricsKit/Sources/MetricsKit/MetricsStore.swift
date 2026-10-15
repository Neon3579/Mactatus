import AppKit
import Foundation
import Observation

/// 실제 측정은 메인 스레드 밖(액터)에서 한다.
actor SystemMonitor {
    private let cpu = CPUSampler()
    private let processes = ProcessSampler()
    private let memory = MemorySampler()
    private let disk = DiskSampler()
    private let network = NetworkSampler()
    private lazy var sensors = TemperatureSensors()
    private var battery: (reading: BatteryReading?, at: Date)?
    private var sensorReading: (reading: SensorReading, at: Date)?
    private var slow: (disk: DiskReading?, processes: [ProcessReading], at: Date)?

    /// - Parameter detailed: 팝오버가 열려 있으면 전부, 닫혀 있으면 메뉴바에 필요한 CPU·메모리만.
    /// 비용에 따라 주기를 나눈다: CPU·메모리·GPU·네트워크 매번, 디스크·프로세스 2초, 배터리 5초, 온도 10초.
    func sample(detailed: Bool, processLimit: Int) -> SystemSnapshot {
        let now = Date()
        var snapshot = SystemSnapshot(date: now, cpu: cpu.sample(), memory: memory.sample())
        guard detailed else { return snapshot }
        snapshot.gpu = GPUReader.utilization()
        snapshot.network = network.sample()
        if slow == nil || now.timeIntervalSince(slow!.at) >= 1.9 {
            slow = (disk.sample(), processes.sample(limit: processLimit), now)
        }
        snapshot.disk = slow?.disk
        snapshot.processes = slow?.processes ?? []
        if battery == nil || now.timeIntervalSince(battery!.at) >= 10 {
            battery = (BatteryReader.read(), now)
        }
        snapshot.battery = battery?.reading
        if sensorReading == nil || now.timeIntervalSince(sensorReading!.at) >= 10 {
            let soc = sensors.socTemperature()
            let thermal: ThermalLevel = switch ProcessInfo.processInfo.thermalState {
            case .nominal: .nominal
            case .fair: .fair
            case .serious: .serious
            case .critical: .critical
            @unknown default: .nominal
            }
            sensorReading = (SensorReading(socTemperature: soc?.average, socTemperatureMax: soc?.max, thermal: thermal), now)
        }
        snapshot.sensors = sensorReading?.reading
        return snapshot
    }
}

/// 최근 값들(그래프용).
public struct MetricsHistory: Sendable, Equatable {
    public static let capacity = 60
    public var cpu: [Double] = []
    public var memory: [Double] = []
    public var gpu: [Double] = []
    public var networkDown: [Double] = []
    public var networkUp: [Double] = []

    mutating func append(_ snapshot: SystemSnapshot) {
        func push(_ array: inout [Double], _ value: Double?) {
            guard let value else { return }
            array.append(value)
            if array.count > Self.capacity { array.removeFirst(array.count - Self.capacity) }
        }
        push(&cpu, snapshot.cpu?.total)
        push(&memory, snapshot.memory?.usedFraction)
        push(&gpu, snapshot.gpu)
        push(&networkDown, snapshot.network?.downRate)
        push(&networkUp, snapshot.network?.upRate)
    }
}

/// 메뉴바 라벨에 쓰는 값. 팝오버가 열려 있어도 5초에 한 번만 바뀐다(라벨을 다시 그리는 비용이 커서).
public struct MenuBarValues: Sendable, Equatable {
    public var cpu: Double?
    public var memory: Double?
    public var cpuHistory: [Double] = []
}

/// 측정 주기 관리: 팝오버가 열려 있으면 1초, 닫혀 있으면 5초(저전력 모드 10초),
/// 화면이 잠기거나 꺼지면 멈춘다.
@MainActor
@Observable
public final class MetricsStore {
    public private(set) var snapshot: SystemSnapshot?
    public private(set) var history = MetricsHistory()
    public private(set) var menuBar = MenuBarValues()
    @ObservationIgnored private var menuBarUpdatedAt = Date.distantPast
    /// 팝오버가 열려 있는지. 바뀌면 바로 한 번 측정한다.
    public var detailVisible = false {
        didSet { if detailVisible != oldValue { sleeper?.cancel() } }
    }
    public var processLimit = 10

    @ObservationIgnored private let monitor = SystemMonitor()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var sleeper: Task<Void, Never>?
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    public init() {}

    public func start() {
        guard loop == nil else { return }
        observePauses()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !paused {
                    let next = await monitor.sample(detailed: detailVisible, processLimit: processLimit)
                    snapshot = next
                    history.append(next)
                    if next.date.timeIntervalSince(menuBarUpdatedAt) >= 4.5 {
                        menuBarUpdatedAt = next.date
                        menuBar = MenuBarValues(cpu: next.cpu?.total, memory: next.memory?.usedFraction,
                                                cpuHistory: Array(history.cpu.suffix(30)))
                    }
                }
                let interval: Double = detailVisible ? 1 : (ProcessInfo.processInfo.isLowPowerModeEnabled ? 10 : 5)
                let wait = Task { _ = try? await Task.sleep(for: .seconds(interval)) }
                sleeper = wait
                await wait.value
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    private func observePauses() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let pairs: [(NotificationCenter, Notification.Name, Bool)] = [
            (workspace, NSWorkspace.screensDidSleepNotification, true),
            (workspace, NSWorkspace.screensDidWakeNotification, false),
            (distributed, Notification.Name("com.apple.screenIsLocked"), true),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), false),
        ]
        for (center, name, pause) in pairs {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.paused = pause
                    if !pause { self?.sleeper?.cancel() }
                }
            })
        }
    }
}
