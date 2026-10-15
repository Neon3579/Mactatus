import CoreKit
import MetricsKit
import SwiftUI
import UsageKit

/// 시스템 설정처럼 왼쪽 사이드바가 있는 설정 창.
struct SettingsView: View {
    let settings: AppSettings
    let usage: UsageStore
    let metrics: MetricsStore
    let loginItem: LoginItem

    enum Pane: String, CaseIterable, Identifiable {
        case general = "일반"
        case usage = "AI 사용량"
        case system = "시스템 리소스"

        var id: Self { self }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .usage: "gauge.with.dots.needle.67percent"
            case .system: "cpu"
            }
        }
    }

    @State private var selection: Pane = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selection) { pane in
                Label(pane.rawValue, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection {
            case .general: GeneralPane(loginItem: loginItem)
            case .usage: UsagePane(settings: settings, usage: usage)
            case .system: SystemPane(settings: settings)
            }
        }
        .frame(width: 660, height: 460)
    }
}

private struct GeneralPane: View {
    let loginItem: LoginItem

    var body: some View {
        Form {
            Section {
                Toggle("로그인할 때 자동으로 실행", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                if let message = loginItem.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 빌드")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("일반")
    }
}

private struct UsagePane: View {
    @Bindable var settings: AppSettings
    let usage: UsageStore

    var body: some View {
        Form {
            Section("서비스") {
                Toggle("Claude Code", isOn: $settings.claudeEnabled)
                Toggle("Codex", isOn: $settings.codexEnabled)
                Toggle(isOn: $settings.geminiEnabled) {
                    Text("Gemini")
                    Text("Gemini CLI 한도를 못 읽으면 Antigravity 한도를 보여줘요.")
                }
            }
            Section("조회") {
                Picker("새로 고침 주기", selection: $settings.refreshMinutes) {
                    ForEach([1, 3, 5, 10, 15], id: \.self) { Text("\($0)분").tag($0) }
                }
            }
            Section("알림") {
                Toggle("한도 알림", isOn: $settings.alertsEnabled)
                Stepper("주의: \(settings.warnPercent)%", value: $settings.warnPercent, in: 50...95, step: 5)
                    .disabled(!settings.alertsEnabled)
                Stepper("위험: \(settings.criticalPercent)%", value: $settings.criticalPercent, in: 60...100, step: 5)
                    .disabled(!settings.alertsEnabled)
                Toggle("한도가 리셋되면 알림", isOn: $settings.resetAlertsEnabled)
                    .disabled(!settings.alertsEnabled)
            }
            Section("Claude Code") {
                Toggle(isOn: $settings.claudeCLIRefresh) {
                    Text("토큰이 만료되면 claude로 다시 읽기")
                    Text("모델 요청 없이 `claude -p /usage`를 실행해요. 사용량을 쓰지 않고, 30분에 한 번까지만 실행해요.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI 사용량")
        .onChange(of: [settings.claudeEnabled, settings.codexEnabled, settings.geminiEnabled]) {
            Task { await usage.refresh() }
        }
    }
}

private struct SystemPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("메뉴바") {
                Toggle("메뉴바에 시스템 리소스 아이콘 보이기", isOn: $settings.systemMenuEnabled)
                Picker("표시 방식", selection: $settings.systemLabelStyle) {
                    ForEach(SystemLabelStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .disabled(!settings.systemMenuEnabled)
            }
            Section("팝오버") {
                Stepper(settings.processCount == 0 ? "CPU 상위 프로세스 숨김" : "CPU 상위 프로세스 \(settings.processCount)개",
                        value: $settings.processCount, in: 0...10)
                Text("팝오버가 열려 있을 때만 1초마다 측정하고, 닫혀 있으면 5초(저전력 모드 10초)마다 CPU·메모리만 측정해요. 화면이 잠기면 멈춰요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("시스템 리소스")
    }
}
