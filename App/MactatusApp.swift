import AppKit
import CoreKit
import MetricsKit
import SwiftUI
import UsageKit

@main
struct MactatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(store: app.usage)
        } label: {
            UsageMenuLabel(store: app.usage)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: Binding(get: { app.settings.systemMenuEnabled },
                                         set: { app.settings.systemMenuEnabled = $0 })) {
            SystemPopover(store: app.metrics, settings: app.settings)
        } label: {
            SystemMenuLabel(store: app.metrics, settings: app.settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: app.settings, usage: app.usage, metrics: app.metrics, loginItem: app.loginItem)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let loginItem = LoginItem()
    let metrics = MetricsStore()
    private var alerts: UsageAlerts?

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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        // 잠자기에서 깨면 네트워크가 붙을 때까지 잠깐 기다렸다 다시 조회
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                await self?.usage.refresh()
            }
        }
        Log.app.info("Mactatus 시작")
    }
}
