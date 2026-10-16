import AppKit
import CoreKit
import DrawerKit
import MetricsKit
import Modules
import NotchKit
import SwiftUI
import UsageKit

@main
struct MactatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        // 메뉴바 아이템(AI 사용량·시스템)과 설정 창은 AppDelegate가 직접 만든다(StatusItemHost.swift 참고).
        // App에는 장면이 하나 있어야 해서 빈 설정 장면만 둔다.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let loginItem = LoginItem()
    let metrics = MetricsStore()
    let drawer = DrawerController()
    private var alerts: UsageAlerts?
    private lazy var notch = NotchHub(settings: settings)
    private var usageItem: StatusItemHost?
    private var terminationSignal: DispatchSourceSignal?
    private var systemItem: StatusItemHost?

    private lazy var settingsWindow = SettingsWindow { [unowned self] in
        AnyView(SettingsView(settings: settings, usage: usage, metrics: metrics, drawer: drawer, notch: notch, loginItem: loginItem))
    }

    lazy var usage: UsageStore = {
        let settings = settings
        return UsageStore(
            providers: [
                ClaudeProvider(allowCLI: { await MainActor.run { settings.claudeCLIRefresh } }),
                CodexProvider(),
                GeminiProvider(),
            ],
            isEnabled: { id in
                switch id {
                case .claude: settings.claudeEnabled
                case .codex: settings.codexEnabled
                case .gemini: settings.geminiEnabled
                }
            },
            interval: { TimeInterval(max(settings.refreshMinutes, 1) * 60) })
    }()

    func applicationWillTerminate(_ notification: Notification) {
        MediaAdapter.terminateRunning()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // pkill 등으로 끝낼 때(SIGTERM)도 정상 종료 과정을 거쳐 음악 어댑터(perl)를 같이 끈다
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        termination.resume()
        terminationSignal = termination
        // Info.plist의 LSUIElement가 없을 때(swift run)도 Dock에 안 뜨게
        NSApp.setActivationPolicy(.accessory)
        if let directory = DebugSnapshot.outputDirectory {
            Task {
                metrics.detailVisible = true
                metrics.start()
                await usage.refresh()
                try? await Task.sleep(for: .seconds(3))
                DebugSnapshot.write(UsagePopover(store: usage), to: directory, name: "usage-popover")
                DebugSnapshot.write(SystemPopover(store: metrics, settings: settings), to: directory, name: "system-popover")
                DebugSnapshot.write(DrawerSnapshotPreview(trusted: true), to: directory, name: "drawer", width: 320)
                DebugSnapshot.write(DrawerSnapshotPreview(trusted: false), to: directory, name: "drawer-permission", width: 320)
                let song = NowPlaying(bundleID: "com.apple.Music", title: "Snapshot Song", artist: "Mactatus", album: "Preview",
                                      isPlaying: true, duration: 214, elapsed: 75, timestamp: .now, playbackRate: 1)
                for (name, expanded, playing) in [("notch-compact", false, song as NowPlaying?), ("notch-expanded", true, song), ("notch-empty", true, nil)] {
                    let media = MediaModule(paths: nil)
                    media.showPreview(playing)
                    let notch = NotchController()
                    notch.modules = [media]
                    DebugSnapshot.write(notch.previewView(expanded: expanded), to: directory, name: name, width: 548)
                }
                let airpods = BluetoothDeviceInfo(id: "preview", name: "AirPods Pro", symbol: "airpodspro",
                                                  battery: BatteryLevels(left: 85, right: 80, caseLevel: 60))
                let events: [(String, @MainActor (NotchController) -> Void)] = [
                    ("notch-bluetooth", { notch in let bt = BluetoothModule(); bt.showPreview(airpods, isConnected: true); notch.modules = [bt] }),
                    ("notch-bluetooth-long", { notch in let bt = BluetoothModule()
                        bt.showPreview(BluetoothDeviceInfo(id: "long", name: "홍길동의 AirPods Pro", symbol: "airpodspro", battery: BatteryLevels()), isConnected: true)
                        notch.modules = [bt] }),
                    ("notch-download", { notch in let dl = DownloadsModule()
                        dl.showPreview(active: [DownloadItem(id: "a", name: "Xcode.xip", fraction: 0.42, secondsRemaining: 150)], recent: [], finished: nil)
                        notch.modules = [dl] }),
                    ("notch-charging", { notch in let st = StatusModule(); st.showPreview(.charging(percent: 80)); notch.modules = [st] }),
                ]
                for (name, setup) in events {
                    let notch = NotchController()
                    setup(notch)
                    DebugSnapshot.write(notch.previewView(expanded: false), to: directory, name: name, width: 548)
                }
                let btExpanded = NotchController()
                let bt = BluetoothModule()
                bt.showPreview(airpods, isConnected: true)
                btExpanded.modules = [bt]
                DebugSnapshot.write(btExpanded.previewView(expanded: true), to: directory, name: "notch-bluetooth-expanded", width: 548)
                DebugSnapshot.write(HStack(spacing: 16) {
                    ForEach(SystemLabelStyle.allCases, id: \.self) { style in
                        SystemMenuLabelPreview(store: self.metrics, style: style)
                    }
                    UsageMenuLabel(store: self.usage)
                }.padding(8), to: directory, name: "menu-labels", width: 340)
                exit(0)
            }
            return
        }
        let alerts = UsageAlerts(settings: settings)
        self.alerts = alerts
        usage.onSnapshot = { alerts.handle($0) }
        usage.start()
        // 개발 확인용: 팝오버가 열린 것처럼 1초마다 전부 측정(성능 측정에 씀)
        if CommandLine.arguments.contains("--metrics-detail") { metrics.detailVisible = true }
        metrics.start()
        drawer.makePanelContent = { [unowned self] in AnyView(DrawerView(controller: drawer)) }
        if settings.drawerEnabled { drawer.start() }
        Task { await installStatusItems() }
        notch.controller.onOpenSettings = { [unowned self] in openSettings() }
        notch.apply()
        // 잠자기에서 깨면 네트워크가 붙을 때까지 잠깐 기다렸다 다시 조회
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                await self?.usage.refresh()
            }
        }
        Log.app.info("Mactatus 시작")
    }

    // MARK: - 메뉴바 아이템(AI 사용량·시스템)

    private func openSettings() {
        usageItem?.closePanel()
        systemItem?.closePanel()
        settingsWindow.show()
    }

    private func installStatusItems() async {
        let open = OpenAppSettingsAction { [weak self] in self?.openSettings() }
        usageItem = StatusItemHost(
            name: "mactatus.usage", title: "AI 사용량",
            label: { [unowned self] in AnyView(UsageMenuLabel(store: usage)) },
            content: { [unowned self] in AnyView(UsagePopover(store: usage).environment(\.openAppSettings, open)) })
        systemItem = StatusItemHost(
            name: "mactatus.system", title: "시스템 리소스",
            label: { [unowned self] in AnyView(SystemMenuLabel(store: metrics, settings: settings)) },
            content: { [unowned self] in AnyView(SystemPopover(store: metrics, settings: settings).environment(\.openAppSettings, open)) })
        usageItem?.install(position: Self.itemPosition(order: 1))
        syncSystemItem()
        observeSystemMenuSetting()
    }

    /// 처음 놓일 위치값(클수록 왼쪽). macOS 27에서는 실제 x와 비례하지 않는 순서값이라 ⌄ 위치로 계산할 수 없다.
    /// 437(⌄ 바로 오른쪽을 노린 거리값)은 ⌄ 왼쪽 맨 끝으로 가서 숨었고, 150은 시스템 아이콘들 사이(⌄ 오른쪽)에 놓였다(macOS 27.0.1).
    /// 그 뒤로는 macOS가 자리를 기억하므로 ⌘-끌기로 옮긴 자리가 유지된다. 시스템이 AI보다 왼쪽.
    static func itemPosition(order: Int) -> CGFloat { 150 - CGFloat(order) * 2 }

    private func syncSystemItem() {
        if settings.systemMenuEnabled {
            systemItem?.install(position: Self.itemPosition(order: 0))
        } else {
            systemItem?.uninstall()
        }
    }

    private func observeSystemMenuSetting() {
        withObservationTracking {
            _ = settings.systemMenuEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncSystemItem()
                self?.observeSystemMenuSetting()
            }
        }
    }
}
