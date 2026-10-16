import CoreKit
import DrawerKit
import MetricsKit
import SwiftUI
import UsageKit

/// 시스템 설정처럼 왼쪽 사이드바가 있는 설정 창.
struct SettingsView: View {
    let settings: AppSettings
    let usage: UsageStore
    let metrics: MetricsStore
    let drawer: DrawerController
    let notch: NotchHub
    let loginItem: LoginItem
    var onShowOnboarding: () -> Void = {}

    enum Pane: String, CaseIterable, Identifiable {
        case general = "일반"
        case usage = "AI 사용량"
        case system = "시스템 리소스"
        case drawer = "메뉴바 서랍"
        case notch = "노치 허브"

        var id: Self { self }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .usage: "gauge.with.dots.needle.67percent"
            case .system: "cpu"
            case .drawer: "chevron.down.square"
            case .notch: "rectangle.topthird.inset.filled"
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
            case .general: GeneralPane(loginItem: loginItem, onShowOnboarding: onShowOnboarding)
            case .usage: UsagePane(settings: settings, usage: usage)
            case .system: SystemPane(settings: settings)
            case .drawer: DrawerPane(settings: settings, drawer: drawer)
            case .notch: NotchPane(settings: settings, notch: notch)
            }
        }
        .frame(width: 660, height: 460)
    }
}

private struct GeneralPane: View {
    let loginItem: LoginItem
    let onShowOnboarding: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("로그인할 때 자동으로 실행", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                if let message = loginItem.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("처음 안내 다시 보기…", action: onShowOnboarding)
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

private struct NotchPane: View {
    @Bindable var settings: AppSettings
    let notch: NotchHub

    var body: some View {
        Form {
            Section {
                Toggle("노치 허브 쓰기", isOn: $settings.notchEnabled)
                Text("내장 디스플레이의 노치 둘레에 보여요. 노치에 마우스를 올리면 펼쳐져요. 외장 모니터에는 띄우지 않아요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("모듈") {
                Toggle("음악", isOn: $settings.mediaEnabled)
                if !notch.media.isAvailable {
                    Label("음악 정보를 읽는 mediaremote-adapter가 앱 안에 없어요.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle("다운로드 진행·완료", isOn: $settings.downloadsEnabled)
                Toggle("블루투스 기기 연결·끊김", isOn: $settings.bluetoothEnabled)
                Toggle("상태 팝업(충전·저전력 모드·Caps Lock)", isOn: $settings.statusEnabled)
                Toggle("볼륨 팝업", isOn: $settings.statusVolumeEnabled)
                    .disabled(!settings.statusEnabled)
                Text("볼륨을 바꾸면 macOS 기본 볼륨 팝업도 함께 떠요.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("새 스크린샷 알림", isOn: $settings.screenshotEnabled)
            }
            .disabled(!settings.notchEnabled)
            Section("파일 트레이") {
                Toggle("파일 트레이 쓰기", isOn: $settings.trayEnabled)
                Toggle("원본 대신 복사본 보관", isOn: $settings.trayKeepsCopies)
                Picker("자동으로 비우기", selection: $settings.trayClearHours) {
                    Text("1시간 뒤").tag(1)
                    Text("하루 뒤").tag(24)
                    Text("일주일 뒤").tag(168)
                    Text("비우지 않음").tag(0)
                }
                Text("파일을 끌어 노치에 가져가면 트레이가 펼쳐져요. 복사본을 보관하면 원본을 옮기거나 지워도 남아요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!settings.notchEnabled)
            Section("클립보드 기록") {
                Toggle("클립보드 기록 쓰기", isOn: $settings.clipboardEnabled)
                Toggle("⌘⇧V로 기록 창 열기", isOn: $settings.clipboardHotkeyEnabled)
                    .disabled(!settings.clipboardEnabled)
                Picker("남길 개수", selection: $settings.clipboardLimit) {
                    Text("20개").tag(20)
                    Text("50개").tag(50)
                    Text("100개").tag(100)
                }
                .disabled(!settings.clipboardEnabled)
                Text("복사한 글·이미지·파일과 클립보드로 찍은 스크린샷, 파일로 저장된 새 스크린샷을 기록해요. 이 맥에만 저장되고, 비밀번호 관리자가 표시한 내용은 남기지 않아요. 켜면 macOS가 다른 앱에서 붙여넣기를 허용할지 물을 수 있어요. ⌘⇧V 창에서 고르면 바로 붙여넣어요(손쉬운 사용 권한 필요).")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!settings.notchEnabled)
        }
        .formStyle(.grouped)
        .navigationTitle("노치 허브")
        .onChange(of: settings.notchEnabled) { notch.apply() }
        .onChange(of: settings.mediaEnabled) { notch.apply() }
        .onChange(of: settings.downloadsEnabled) { notch.apply() }
        .onChange(of: settings.bluetoothEnabled) { notch.apply() }
        .onChange(of: settings.statusEnabled) { notch.apply() }
        .onChange(of: settings.statusVolumeEnabled) { notch.apply() }
        .onChange(of: settings.trayEnabled) { notch.apply() }
        .onChange(of: settings.trayKeepsCopies) { notch.apply() }
        .onChange(of: settings.trayClearHours) { notch.apply() }
        .onChange(of: settings.screenshotEnabled) { notch.apply() }
        .onChange(of: settings.clipboardEnabled) { notch.apply() }
        .onChange(of: settings.clipboardLimit) { notch.apply() }
        .onChange(of: settings.clipboardHotkeyEnabled) { notch.apply() }
    }
}

private struct DrawerPane: View {
    @Bindable var settings: AppSettings
    let drawer: DrawerController

    var body: some View {
        Form {
            Section {
                Toggle("메뉴바 서랍(⌄) 쓰기", isOn: $settings.drawerEnabled)
                Text("서랍에는 다른 앱의 메뉴바 아이콘이 모두 보이고, 누르면 원래 메뉴가 열려요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("권한") {
                LabeledContent("손쉬운 사용") {
                    if drawer.isTrusted {
                        Label("허용됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("권한 켜기…") { drawer.requestAccessibility() }
                    }
                }
            }
            Section("메뉴바에서 아이콘 숨기기") {
                Text("시스템 설정 → 메뉴 막대 → \"메뉴 막대에서 허용\"에서 앱을 끄면 그 아이콘이 메뉴바와 « 에서 사라져요. 앱은 계속 실행되고, 서랍에서 눌러 열 수 있어요. Wi-Fi·Spotlight 같은 Apple 기능은 같은 화면 위쪽에서 \"메뉴 막대에서 보지 않음\"으로 바꿔요.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("메뉴 막대 설정 열기…") { NSWorkspace.shared.open(DrawerController.menuBarSettingsURL) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("메뉴바 서랍")
        .onChange(of: settings.drawerEnabled) { _, enabled in
            enabled ? drawer.start() : drawer.stop()
        }
    }
}
