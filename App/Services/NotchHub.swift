import CoreKit
import Modules
import NotchKit

/// 노치 허브와 그 안의 모듈을 설정에 맞춰 켜고 끈다.
@MainActor
final class NotchHub {
    let controller = NotchController()
    let media = MediaModule()
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 설정이 바뀔 때마다 부른다.
    func apply() {
        guard settings.notchEnabled else {
            controller.stop()
            media.stop()
            return
        }
        if settings.mediaEnabled {
            media.start()
        } else {
            media.stop()
        }
        controller.modules = settings.mediaEnabled ? [media] : []
        controller.start()
    }
}
