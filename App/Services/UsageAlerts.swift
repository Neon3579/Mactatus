import CoreKit
import Foundation
import UsageKit
import UserNotifications

/// 한도가 주의·위험 기준을 넘으면(같은 리셋 주기에 한 번씩) macOS 알림을 보낸다.
@MainActor
final class UsageAlerts {
    private let settings: AppSettings
    private let center: UNUserNotificationCenter?
    private let presenter = NotificationPresenter()
    /// 리셋 주기별로 이미 알린 가장 높은 기준.
    private var notifiedLevel: [String: Int] = [:]
    private var lastPercent: [String: Double] = [:]

    init(settings: AppSettings) {
        self.settings = settings
        // .app으로 묶이지 않은 실행(swift run)에서는 알림 센터를 쓸 수 없다
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        center?.delegate = presenter
        if settings.alertsEnabled, let center {
            Task { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
        }
    }

    func handle(_ snapshot: UsageSnapshot) {
        guard settings.alertsEnabled else { return }
        for window in snapshot.windows {
            let key = "\(snapshot.provider.rawValue).\(window.id)"
            let previous = lastPercent[key]
            lastPercent[key] = window.usedPercent

            // 리셋 시각(시간 단위)으로 주기를 구분한다
            let cycle = key + "@" + (window.resetsAt.map { String(Int($0.timeIntervalSince1970 / 3600)) } ?? "-")
            let level = window.usedPercent >= Double(settings.criticalPercent) ? settings.criticalPercent
                : window.usedPercent >= Double(settings.warnPercent) ? settings.warnPercent : 0
            if level > notifiedLevel[cycle, default: 0] {
                notifiedLevel[cycle] = level
                post(id: cycle,
                     title: "\(snapshot.provider.displayName) \(window.title) 한도 \(Int(window.usedPercent.rounded()))%",
                     body: UsageFormat.resetText(window.resetsAt).map { "\($0)돼요." } ?? "남은 한도를 확인해 주세요.")
            }

            if settings.resetAlertsEnabled, let previous, previous >= Double(settings.warnPercent), window.usedPercent < 10 {
                post(id: key + ".reset", title: "\(snapshot.provider.displayName) \(window.title) 한도가 리셋됐어요", body: "다시 쓸 수 있어요.")
            }
        }
    }

    private func post(id: String, title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

/// 앱이 앞에 있어도 배너를 보여준다.
private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
