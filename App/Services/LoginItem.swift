import Foundation
import Observation
import ServiceManagement

/// 로그인할 때 자동 실행(SMAppService).
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var message: String?

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            message = nil
        } catch {
            message = "설정하지 못했어요: \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        if status == .requiresApproval {
            message = "시스템 설정 → 일반 → 로그인 항목에서 Mactatus를 허용해 주세요."
        }
    }
}
