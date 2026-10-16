import CoreKit
import Modules
import NotchKit

/// 노치 허브와 그 안의 모듈을 설정에 맞춰 켜고 끈다.
@MainActor
final class NotchHub {
    let controller = NotchController()
    let media = MediaModule()
    let downloads = DownloadsModule()
    let bluetooth = BluetoothModule()
    let status = StatusModule()
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 설정이 바뀔 때마다 부른다.
    func apply() {
        guard settings.notchEnabled else {
            controller.stop()
            media.stop()
            downloads.stop()
            bluetooth.stop()
            status.stop()
            return
        }
        settings.mediaEnabled ? media.start() : media.stop()
        settings.downloadsEnabled ? downloads.start() : downloads.stop()
        settings.bluetoothEnabled ? bluetooth.start() : bluetooth.stop()
        status.showsVolume = settings.statusVolumeEnabled
        settings.statusEnabled ? status.start() : status.stop()
        // 펼친 화면의 탭 순서
        var modules: [NotchModule] = []
        if settings.mediaEnabled { modules.append(media) }
        if settings.downloadsEnabled { modules.append(downloads) }
        if settings.bluetoothEnabled { modules.append(bluetooth) }
        if settings.statusEnabled { modules.append(status) }
        controller.modules = modules
        controller.start()
    }
}
