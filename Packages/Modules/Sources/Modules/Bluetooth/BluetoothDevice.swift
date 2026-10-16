import Foundation

/// 연결된 블루투스 기기 한 대.
public struct BluetoothDeviceInfo: Sendable, Equatable, Identifiable {
    /// 기기 주소
    public var id: String
    public var name: String
    public var symbol: String
    public var battery: BatteryLevels

    /// 미니 알림용 짧은 이름: "홍길동의 AirPods Pro"·"Kim's AirPods" → "AirPods Pro"·"AirPods"
    public var shortName: String {
        for marker in ["의 ", "’s ", "'s "] {
            if let range = name.range(of: marker, options: .backwards) {
                let rest = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { return rest }
            }
        }
        return name
    }

    public init(id: String, name: String, symbol: String, battery: BatteryLevels) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.battery = battery
    }
}

/// 기기 배터리(%). AirPods는 왼쪽·오른쪽·케이스, 그 밖의 기기는 하나. 0은 "모름"으로 본다.
public struct BatteryLevels: Sendable, Equatable {
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    public var single: Int?

    public init(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, single: Int? = nil) {
        self.left = Self.valid(left)
        self.right = Self.valid(right)
        self.caseLevel = Self.valid(caseLevel)
        self.single = Self.valid(single)
    }

    private static func valid(_ value: Int?) -> Int? {
        guard let value, (1...100).contains(value) else { return nil }
        return value
    }

    /// 한 숫자로 줄인 값: 하나짜리 기기는 그 값, 이어폰은 낮은 쪽
    public var summary: Int? {
        if let single { return single }
        switch (left, right) {
        case let (l?, r?): return min(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    /// 펼친 화면용 자세한 글: "왼쪽 80% · 오른쪽 85% · 케이스 60%"
    public var detail: String? {
        if let single { return "\(single)%" }
        let parts = [left.map { "왼쪽 \($0)%" }, right.map { "오른쪽 \($0)%" }, caseLevel.map { "케이스 \($0)%" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// 기기 종류에 맞는 SF Symbol.
public enum BluetoothSymbols {
    /// - Parameters:
    ///   - majorClass: 블루투스 기기 분류(0x04 오디오, 0x05 주변기기)
    ///   - minorClass: 세부 분류(주변기기: 0x10 키보드, 0x20 포인팅)
    public static func symbol(name: String, majorClass: UInt32, minorClass: UInt32) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        if lower.contains("trackpad") { return "hand.point.up.left" }
        if lower.contains("mouse") { return "magicmouse" }
        if lower.contains("keyboard") { return "keyboard" }
        switch majorClass {
        case 0x04: return minorClass == 0x05 ? "hifispeaker" : "headphones"
        case 0x05:
            if minorClass & 0x10 != 0 { return "keyboard" }
            if minorClass & 0x20 != 0 { return "computermouse" }
            return "gamecontroller"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
