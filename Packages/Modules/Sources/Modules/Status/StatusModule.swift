import AppKit
import AudioToolbox
import CoreAudio
import IOKit.ps
import NotchKit
import Observation
import SwiftUI

/// 🔊 상태 팝업: 충전 시작·끝, 저전력 모드, Caps Lock, 볼륨(선택)을 노치에 잠깐 보여준다.
/// 펼친 화면에는 탭을 두지 않는다. macOS 기본 볼륨 팝업도 함께 뜨므로 볼륨은 기본으로 끈다.
@MainActor
@Observable
public final class StatusModule: NotchModule {
    public let id = "status"
    public let title = "상태"
    public let symbol = "bolt"

    public enum StatusEvent: Sendable, Equatable {
        case charging(percent: Int?)
        case onBattery(percent: Int?)
        case lowPower(Bool)
        case capsLock(Bool)
        case volume(level: Double, muted: Bool)
    }

    public let flash = NotchFlash<StatusEvent>()
    /// 볼륨 바뀜도 보일지
    public var showsVolume = false {
        didSet { if showsVolume != oldValue, isRunning { showsVolume ? volume.start() : volume.stop() } }
    }

    @ObservationIgnored private var power: PowerWatcher?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var capsLock = NSEvent.modifierFlags.contains(.capsLock)
    @ObservationIgnored private var capsLockCheck: Task<Void, Never>?
    @ObservationIgnored private var capsLockShownAt = Date.distantPast
    @ObservationIgnored private lazy var volume = VolumeWatcher { [weak self] level, muted in
        self?.flash.show(.volume(level: level, muted: muted), for: .seconds(1.5))
    }
    @ObservationIgnored private var isRunning = false

    public init() {}

    public var compactPriority: Int? { flash.value != nil ? NotchPriority.alert : nil }
    public var showsTab: Bool { false }
    public var compactWingWidth: CGFloat {
        switch flash.value {
        case .volume: 64
        case .lowPower, .capsLock: 76
        default: 56
        }
    }

    // MARK: - 켜기·끄기

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        power = PowerWatcher { [weak self] charging, percent in
            self?.flash.show(charging ? .charging(percent: percent) : .onBattery(percent: percent))
        }
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            let on = ProcessInfo.processInfo.isLowPowerModeEnabled
            MainActor.assumeIsolated { self?.flash.show(.lowPower(on)) }
        })
        // Caps Lock: 다른 앱이 앞에 있을 때(전역)와 우리 창일 때(지역) 모두 본다. 전역 키 감시는 손쉬운 사용 권한이 필요하다
        let check: @MainActor (NSEvent) -> Void = { [weak self] _ in self?.scheduleCapsLockCheck() }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            MainActor.assumeIsolated { check(event) }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            MainActor.assumeIsolated { check(event) }
            return event
        } as Any)
        // 한/영 등 입력 소스가 바뀌면(시스템 전체 알림) Caps Lock 팝업을 거른다
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputSourceChanged() }
        })
        if showsVolume { volume.start() }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        power?.invalidate()
        power = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        capsLockCheck?.cancel()
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
        observers.removeAll()
        volume.stop()
        flash.clear()
    }

    /// 스냅샷 확인용
    public func showPreview(_ event: StatusEvent) { flash.show(event, for: .seconds(60)) }

    /// Caps Lock 키로 한/영을 바꾸도록 설정하면, 짧게 눌러 입력 소스만 바꿀 때도 키 이벤트에는 Caps Lock이 켜진 것처럼 온다.
    /// 잠깐(0.2초) 뒤 실제 상태를 읽어 바뀌었을 때만 보여주고, 입력 소스가 바뀌었다는 알림이 오면 한/영 전환으로 보고
    /// 띄우지 않거나 방금 띄운 것을 지운다.
    private func scheduleCapsLockCheck() {
        capsLockCheck?.cancel()
        capsLockCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            let on = NSEvent.modifierFlags.contains(.capsLock)
            guard on != self.capsLock else { return }
            self.capsLock = on
            self.capsLockShownAt = .now
            self.flash.show(.capsLock(on), for: .seconds(1.5))
        }
    }

    private func inputSourceChanged() {
        capsLockCheck?.cancel()
        capsLock = NSEvent.modifierFlags.contains(.capsLock)
        if case .capsLock = flash.value, Date.now.timeIntervalSince(capsLockShownAt) < 0.8 { flash.clear() }
    }

    // MARK: - 노치 화면

    public func compactLeading() -> AnyView { AnyView(StatusCompactIcon(event: flash.value)) }
    public func compactTrailing() -> AnyView { AnyView(StatusCompactValue(event: flash.value)) }
    public func expanded() -> AnyView { AnyView(EmptyView()) }
}

// MARK: - 전원

/// 전원 어댑터를 꽂거나 뺄 때 알려 준다(IOKit 전원 알림).
@MainActor
private final class PowerWatcher {
    private var source: CFRunLoopSource?
    private var lastConnected: Bool?
    private let onChange: (Bool, Int?) -> Void

    init(onChange: @escaping (Bool, Int?) -> Void) {
        self.onChange = onChange
        lastConnected = Self.read().connected
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let watcher = Unmanaged<PowerWatcher>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.changed() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    /// 알림을 그만 받는다(끌 때 부른다)
    func invalidate() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    private func changed() {
        let state = Self.read()
        guard state.connected != lastConnected else { return }
        lastConnected = state.connected
        onChange(state.connected, state.percent)
    }

    /// 어댑터 연결 여부와 배터리 %(배터리가 없는 맥이면 nil)
    static func read() -> (connected: Bool, percent: Int?) {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let connected = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            let percent = current.flatMap { c in maximum.map { $0 > 0 ? c * 100 / $0 : c } }
            return (connected, percent)
        }
        return (true, nil)
    }
}

// MARK: - 볼륨

/// 기본 출력 기기의 볼륨·음소거가 바뀔 때 알려 준다(CoreAudio).
@MainActor
private final class VolumeWatcher {
    private let onChange: (Double, Bool) -> Void
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var listener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    init(onChange: @escaping (Double, Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard deviceListener == nil else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attach() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListener)
        self.deviceListener = deviceListener
        attach()
    }

    func stop() {
        detach()
        if let deviceListener {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListener)
        }
        deviceListener = nil
    }

    /// 기본 출력 기기가 바뀌면 새 기기에 다시 붙는다.
    private func attach() {
        detach()
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onChange(self.level(), self.muted())
            }
        }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var property = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            AudioObjectAddPropertyListenerBlock(device, &property, .main, listener)
        }
        self.listener = listener
    }

    private func detach() {
        guard let listener, device != kAudioObjectUnknown else { return }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var property = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            AudioObjectRemovePropertyListenerBlock(device, &property, .main, listener)
        }
        self.listener = nil
    }

    private func level() -> Double {
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return Double(value)
    }

    private func muted() -> Bool {
        var address = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value != 0
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

// MARK: - 화면

/// 미니(왼쪽): 무슨 일인지 그림으로
struct StatusCompactIcon: View {
    let event: StatusModule.StatusEvent?

    var body: some View {
        Group {
            switch event {
            case .charging: Image(systemName: "bolt.fill").foregroundStyle(.green)
            case .onBattery: Image(systemName: "battery.75percent")
            case .lowPower(let on): Image(systemName: on ? "battery.25percent" : "battery.100percent").foregroundStyle(on ? .yellow : .white)
            case .capsLock(let on): Image(systemName: on ? "capslock.fill" : "capslock").foregroundStyle(on ? .green : .secondary)
            case .volume(let level, let muted): Image(systemName: Self.speaker(level: level, muted: muted))
            case nil: EmptyView()
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
    }

    static func speaker(level: Double, muted: Bool) -> String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        switch level {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// 미니(오른쪽): 값(배터리 %, 켬/끔, 볼륨 막대)
struct StatusCompactValue: View {
    let event: StatusModule.StatusEvent?

    var body: some View {
        Group {
            switch event {
            case .charging(let percent): Text(percent.map { "\($0)%" } ?? "충전 중")
            case .onBattery(let percent): Text(percent.map { "\($0)%" } ?? "배터리")
            case .lowPower(let on): Text(on ? "저전력 켬" : "저전력 끔")
            case .capsLock(let on): Text(on ? "켬" : "끔")
            case .volume(let level, let muted):
                Capsule().fill(.white.opacity(0.2))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(.white).frame(width: proxy.size.width * (muted ? 0 : min(max(level, 0), 1)))
                        }
                    }
                    .frame(width: 40, height: 5)
            case nil: EmptyView()
            }
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 6)
    }
}
