// 비공식: AirPods 배터리는 IOBluetoothDevice의 공개되지 않은 속성(batteryPercentLeft·Right·Case·Single)으로 읽는다.
// macOS 27.0.1에서 확인(docs/spike-results.md 6번). 속성이 없으면 배터리만 빼고 보여준다.
import AppKit
import IOBluetooth
import NotchKit
import Observation
import SwiftUI

/// 🎧 블루투스 모듈: 기기가 연결되거나 끊기면 노치에 잠깐 알리고, 펼치면 연결된 기기와 배터리를 보여준다.
@MainActor
@Observable
public final class BluetoothModule: NotchModule {
    public let id = "bluetooth"
    public let title = "블루투스"
    public let symbol = "headphones"

    /// 지금 연결된 기기
    public private(set) var connected: [BluetoothDeviceInfo] = []
    /// 연결·끊김 알림
    public let flash = NotchFlash<BluetoothEvent>()

    public struct BluetoothEvent: Sendable, Equatable {
        public var device: BluetoothDeviceInfo
        public var isConnected: Bool
    }

    @ObservationIgnored private var listener: BluetoothListener?
    @ObservationIgnored private var startedAt = Date.distantPast

    public init() {}

    public var compactPriority: Int? { flash.value != nil ? NotchPriority.alert : nil }
    public var compactWingWidth: CGFloat { 116 }

    // MARK: - 켜기·끄기

    public func start() {
        guard listener == nil else { return }
        let listener = BluetoothListener()
        listener.onConnect = { [weak self] device in self?.connected(device) }
        listener.onDisconnect = { [weak self] device in self?.disconnected(device) }
        self.listener = listener
        startedAt = .now
        Task {
            // 처음 부를 때 블루투스 권한 창이 뜨는데, 창이 떠 있는 동안 호출이 멈추므로 메인 스레드 밖에서 먼저 한 번 부른다
            await Task.detached { _ = IOBluetoothDevice.pairedDevices() }.value
            // 등록하자마자 이미 연결된 기기를 알려 준다(그때는 알림을 띄우지 않음)
            self.startedAt = .now
            listener.register()
        }
    }

    public func stop() {
        listener?.unregister()
        listener = nil
        connected = []
        flash.clear()
    }

    /// 스냅샷 확인용
    public func showPreview(_ device: BluetoothDeviceInfo, isConnected: Bool) {
        connected = isConnected ? [device] : []
        flash.show(BluetoothEvent(device: device, isConnected: isConnected), for: .seconds(60))
    }

    /// 펼칠 때 배터리를 다시 읽는다.
    public func refreshBatteries() {
        connected = connected.map { info in
            guard let device = IOBluetoothDevice(addressString: info.id) else { return info }
            return Self.info(device)
        }
    }

    // MARK: - 이벤트

    private func connected(_ device: IOBluetoothDevice) {
        let info = Self.info(device)
        connected.removeAll { $0.id == info.id }
        connected.append(info)
        // 시작할 때 이미 연결돼 있던 기기는 알리지 않는다
        guard Date.now.timeIntervalSince(startedAt) > 2 else { return }
        flash.show(BluetoothEvent(device: info, isConnected: true), for: .seconds(4))
        // AirPods 배터리는 연결 직후 잠깐 뒤에 들어온다
        Task {
            try? await Task.sleep(for: .seconds(2))
            let updated = Self.info(device)
            if let index = connected.firstIndex(where: { $0.id == updated.id }) { connected[index] = updated }
            flash.update { event in if event.device.id == updated.id { event.device = updated } }
        }
    }

    private func disconnected(_ device: IOBluetoothDevice) {
        let info = connected.first { $0.id == device.addressString } ?? Self.info(device)
        connected.removeAll { $0.id == info.id }
        flash.show(BluetoothEvent(device: info, isConnected: false), for: .seconds(3))
    }

    static func info(_ device: IOBluetoothDevice) -> BluetoothDeviceInfo {
        let name = device.name ?? "블루투스 기기"
        func level(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)) else { return nil }
            return (device.value(forKey: key) as? NSNumber)?.intValue
        }
        return BluetoothDeviceInfo(
            id: device.addressString ?? name,
            name: name,
            symbol: BluetoothSymbols.symbol(name: name, majorClass: device.deviceClassMajor, minorClass: device.deviceClassMinor),
            battery: BatteryLevels(left: level("batteryPercentLeft"), right: level("batteryPercentRight"),
                                   caseLevel: level("batteryPercentCase"), single: level("batteryPercentSingle")))
    }

    // MARK: - 노치 화면

    public func compactLeading() -> AnyView { AnyView(BluetoothCompactName(module: self)) }
    public func compactTrailing() -> AnyView { AnyView(BluetoothCompactStatus(module: self)) }
    public func expanded() -> AnyView { AnyView(BluetoothExpandedView(module: self)) }
}

/// IOBluetooth 알림을 받는 쪽(Objective-C 선택자가 필요해 NSObject).
/// 알림은 IOBluetooth 내부 큐(com.apple.bluetooth.iobluetooth.coordinatorQueue)에서 오므로 받자마자 메인으로 넘긴다.
/// (메인 액터로 표시해 두면 그 큐에서 불릴 때 Swift가 격리 검사로 앱을 멈춘다 — macOS 27.0.1, AirPods 연결 때 확인)
private final class BluetoothListener: NSObject, @unchecked Sendable {
    // 아래 값들은 메인 스레드에서만 다룬다
    @MainActor var onConnect: ((IOBluetoothDevice) -> Void)?
    @MainActor var onDisconnect: ((IOBluetoothDevice) -> Void)?
    @MainActor private var connectNote: IOBluetoothUserNotification?
    @MainActor private var disconnectNotes: [String: IOBluetoothUserNotification] = [:]

    @MainActor func register() {
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    @MainActor func unregister() {
        connectNote?.unregister()
        connectNote = nil
        disconnectNotes.values.forEach { $0.unregister() }
        disconnectNotes.removeAll()
    }

    @objc nonisolated func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let box = DeviceBox(device)
        DispatchQueue.main.async { MainActor.assumeIsolated { self.handleConnect(box.device) } }
    }

    @objc nonisolated func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let box = DeviceBox(device)
        DispatchQueue.main.async { MainActor.assumeIsolated { self.handleDisconnect(box.device) } }
    }

    @MainActor private func handleConnect(_ device: IOBluetoothDevice) {
        if let address = device.addressString, disconnectNotes[address] == nil {
            disconnectNotes[address] = device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        }
        onConnect?(device)
    }

    @MainActor private func handleDisconnect(_ device: IOBluetoothDevice) {
        if let address = device.addressString { disconnectNotes.removeValue(forKey: address)?.unregister() }
        onDisconnect?(device)
    }
}

/// IOBluetoothDevice를 메인으로 넘기기 위한 상자(메인에서만 쓴다).
private struct DeviceBox: @unchecked Sendable {
    let device: IOBluetoothDevice
    init(_ device: IOBluetoothDevice) { self.device = device }
}

// MARK: - 화면

/// 미니(왼쪽): 기기 그림과 이름
struct BluetoothCompactName: View {
    let module: BluetoothModule

    var body: some View {
        if let event = module.flash.value {
            HStack(spacing: 5) {
                Image(systemName: event.device.symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(event.device.shortName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
        }
    }
}

/// 미니(오른쪽): 배터리 또는 "연결 끊김"
struct BluetoothCompactStatus: View {
    let module: BluetoothModule

    var body: some View {
        if let event = module.flash.value {
            Group {
                if !event.isConnected {
                    Text("연결 끊김").foregroundStyle(.secondary)
                } else if let level = event.device.battery.summary {
                    Label("\(level)%", systemImage: Self.batterySymbol(level))
                        .foregroundStyle(level <= 20 ? .red : .white)
                } else {
                    Text("연결됨").foregroundStyle(.green)
                }
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)
            .accessibilityElement(children: .combine)
        }
    }

    static func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// 펼침: 연결된 기기와 배터리
struct BluetoothExpandedView: View {
    let module: BluetoothModule

    var body: some View {
        Group {
            if module.connected.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "headphones").font(.title2).foregroundStyle(.secondary)
                    Text("연결된 블루투스 기기가 없어요").font(.callout.weight(.medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(module.connected) { device in
                        HStack(spacing: 10) {
                            Image(systemName: device.symbol)
                                .font(.system(size: 18))
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name).font(.callout.weight(.medium)).lineLimit(1)
                                Text(device.battery.detail ?? "배터리 정보 없음")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let level = device.battery.summary {
                                Gauge(value: Double(level), in: 0...100) { EmptyView() }
                                    .gaugeStyle(.accessoryCircularCapacity)
                                    .tint(level <= 20 ? .red : .green)
                                    .scaleEffect(0.6)
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { module.refreshBatteries() }
    }
}
