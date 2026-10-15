import Foundation

public enum CoreKind: Sendable, Equatable {
    case performance, efficiency, unknown
}

public struct CoreReading: Sendable, Equatable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var kind: CoreKind
    /// 0~1
    public var usage: Double
}

public struct CPUReading: Sendable, Equatable {
    /// 0~1
    public var total: Double
    public var user: Double
    public var system: Double
    public var cores: [CoreReading]
}

public struct ProcessReading: Sendable, Equatable, Identifiable {
    public var id: pid_t { pid }
    public var pid: pid_t
    public var name: String
    /// 코어 하나 기준 %(활성 상태 보기와 같음, 100을 넘을 수 있음)
    public var cpuPercent: Double
    public var appPath: String?
}

public enum MemoryPressure: Sendable, Equatable {
    case normal, warning, critical

    public var label: String {
        switch self {
        case .normal: "정상"
        case .warning: "주의"
        case .critical: "위험"
        }
    }
}

public struct MemoryReading: Sendable, Equatable {
    public var total: UInt64
    /// 앱 + 고정 + 압축 (활성 상태 보기의 "사용된 메모리")
    public var used: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public var pressure: MemoryPressure

    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct DiskReading: Sendable, Equatable {
    public var volumeName: String
    public var total: Int64
    public var available: Int64
    /// 초당 바이트
    public var readRate: Double
    public var writeRate: Double

    public var usedFraction: Double { total > 0 ? 1 - Double(available) / Double(total) : 0 }
}

public struct NetworkReading: Sendable, Equatable {
    /// 초당 바이트
    public var downRate: Double
    public var upRate: Double
    public var interfaceName: String?
    public var interfaceDisplayName: String?
    public var address: String?
}

public struct BatteryReading: Sendable, Equatable {
    public var percent: Int
    public var isCharging: Bool
    public var onAC: Bool
    /// 배터리로 버틸 수 있는 시간(분). 계산 중이거나 충전 중이면 nil
    public var minutesRemaining: Int?
    public var minutesToFull: Int?
    public var cycleCount: Int?
    /// 설계 용량 대비 현재 최대 용량(0~1)
    public var health: Double?
    /// 배터리에서 나가는(음수) 또는 들어오는(양수) 전력, W
    public var watts: Double?
    public var adapterWatts: Int?
    public var temperature: Double?
}

public enum ThermalLevel: Sendable, Equatable {
    case nominal, fair, serious, critical

    public var label: String {
        switch self {
        case .nominal: "정상"
        case .fair: "약간 따뜻함"
        case .serious: "뜨거움"
        case .critical: "매우 뜨거움"
        }
    }
}

public struct SensorReading: Sendable, Equatable {
    /// SoC 다이 온도 평균(℃). 읽을 수 없으면 nil
    public var socTemperature: Double?
    public var socTemperatureMax: Double?
    public var thermal: ThermalLevel
}

/// 한 번 측정한 결과. 자세히 보기(팝오버 열림)가 아니면 일부만 채운다.
public struct SystemSnapshot: Sendable, Equatable {
    public var date: Date
    public var cpu: CPUReading?
    public var memory: MemoryReading?
    public var gpu: Double?
    public var disk: DiskReading?
    public var network: NetworkReading?
    public var battery: BatteryReading?
    public var sensors: SensorReading?
    public var processes: [ProcessReading] = []
}
