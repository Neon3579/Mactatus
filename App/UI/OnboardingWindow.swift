import AppKit
import CoreBluetooth
import DrawerKit
import SwiftUI
import UserNotifications

/// 첫 실행 안내 창. 처음 켤 때 한 번 뜨고, 설정 → 일반에서 다시 열 수 있다.
@MainActor
final class OnboardingWindow {
    /// 안내 내용을 크게 바꾸면 올려서 다시 보여준다
    static let version = 1
    private static let key = "onboarding.version"

    private var window: NSWindow?
    private let drawer: DrawerController
    private let loginItem: LoginItem

    init(drawer: DrawerController, loginItem: LoginItem) {
        self.drawer = drawer
        self.loginItem = loginItem
    }

    static var needsShowing: Bool { UserDefaults.standard.integer(forKey: key) < version }

    func show() {
        if window == nil {
            let view = OnboardingView(drawer: drawer, loginItem: loginItem) { [weak self] in self?.finish() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Mactatus 시작하기"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(Self.version, forKey: Self.key)
        window?.close()
    }
}

private struct OnboardingView: View {
    let drawer: DrawerController
    let loginItem: LoginItem
    let onFinish: () -> Void

    @State private var accessibility = AXIsProcessTrusted()
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @State private var bluetooth = CBManager.authorization

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mactatus에 오신 걸 환영해요").font(.title2.weight(.semibold))
                Text("메뉴바에는 AI 사용량·시스템 리소스·서랍(⌄)이, 노치에는 음악·파일 트레이·클립보드·알림이 들어 있어요. 아래 권한을 켜면 모든 기능을 쓸 수 있어요.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                step("hand.raised", "손쉬운 사용",
                     "서랍에서 다른 앱 아이콘 열기, ⌘⇧V로 바로 붙여넣기, Caps Lock 알림에 필요해요.",
                     done: accessibility, action: "권한 켜기…") { drawer.requestAccessibility() }
                Divider()
                step("bell.badge", "알림",
                     "AI 사용량이 한도에 가까워지면 알려 드려요.",
                     done: notifications == .authorized || notifications == .provisional,
                     action: notifications == .notDetermined ? "허용…" : "설정 열기…") { requestNotifications() }
                Divider()
                step("headphones", "블루투스",
                     "AirPods 같은 기기가 연결되거나 끊기면 노치에 배터리와 함께 알려 드려요.",
                     done: bluetooth == .allowedAlways, action: "설정 열기…") {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
                }
                Divider()
                step("menubar.rectangle", "메뉴바 아이콘 정리",
                     "시스템 설정 → 메뉴 막대 → \"메뉴 막대에서 허용\"에서 숨길 앱을 끄세요. 꺼도 ⌄ 서랍에서 눌러 열 수 있어요.",
                     done: nil, action: "메뉴 막대 설정…") { NSWorkspace.shared.open(DrawerController.menuBarSettingsURL) }
                Divider()
                step("doc.on.clipboard", "처음 쓸 때 묻는 것",
                     "클립보드 기록은 처음 복사할 때 붙여넣기 허용을, 다운로드·스크린샷은 다운로드·데스크톱 폴더 접근을 물어요. \"허용\"을 눌러 주세요.",
                     done: nil, action: nil) {}
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Toggle("로그인할 때 자동으로 실행", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
            if let message = loginItem.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Text("설정 → 일반에서 이 안내를 다시 볼 수 있어요.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("시작하기", action: onFinish)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 520)
        // 시스템 설정에서 권한을 바꾸고 돌아오면 바로 반영되게 1초마다 다시 읽는다
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func step(_ symbol: String, _ title: String, _ detail: String, done: Bool?, action: String?,
                      perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if done == true {
                        Label("켜짐", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)
                            .accessibilityLabel("켜짐")
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action, done != true {
                Button(action, action: perform).controlSize(.small)
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
    }

    private func refresh() async {
        accessibility = AXIsProcessTrusted()
        bluetooth = CBManager.authorization
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func requestNotifications() {
        if notifications == .notDetermined {
            Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        } else {
            open("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
