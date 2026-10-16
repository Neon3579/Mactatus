import Carbon.HIToolbox
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
    let tray = FileTrayModule()
    let screenshot = ScreenshotModule()
    let clipboard = ClipboardModule()
    private let settings: AppSettings
    private lazy var clipboardPopup = ClipboardPopup(module: clipboard)
    private var clipboardHotKey: HotKey?

    init(settings: AppSettings) {
        self.settings = settings
        // 파일로 저장된 새 스크린샷도 클립보드 기록에 넣는다(기록이 켜져 있을 때만 받아들임)
        screenshot.onNewScreenshot = { [weak self] url in self?.clipboard.addScreenshot(url) }
    }

    /// 설정이 바뀔 때마다 부른다.
    func apply() {
        guard settings.notchEnabled else {
            controller.stop()
            let all: [NotchModule] = [media, downloads, bluetooth, status, tray, screenshot, clipboard]
            all.forEach { stop($0) }
            setClipboardHotKey(false)
            return
        }
        settings.mediaEnabled ? media.start() : media.stop()
        settings.downloadsEnabled ? downloads.start() : downloads.stop()
        settings.bluetoothEnabled ? bluetooth.start() : bluetooth.stop()
        status.showsVolume = settings.statusVolumeEnabled
        settings.statusEnabled ? status.start() : status.stop()
        tray.keepsCopies = settings.trayKeepsCopies
        tray.clearAfterHours = settings.trayClearHours
        settings.trayEnabled ? tray.start() : tray.stop()
        settings.screenshotEnabled ? screenshot.start() : screenshot.stop()
        clipboard.limit = max(settings.clipboardLimit, 10)
        settings.clipboardEnabled ? clipboard.start() : clipboard.stop()
        setClipboardHotKey(settings.clipboardEnabled && settings.clipboardHotkeyEnabled)
        // 펼친 화면의 탭 순서
        var modules: [NotchModule] = []
        if settings.mediaEnabled { modules.append(media) }
        if settings.trayEnabled { modules.append(tray) }
        if settings.clipboardEnabled { modules.append(clipboard) }
        if settings.screenshotEnabled { modules.append(screenshot) }
        if settings.downloadsEnabled { modules.append(downloads) }
        if settings.bluetoothEnabled { modules.append(bluetooth) }
        if settings.statusEnabled { modules.append(status) }
        controller.modules = modules
        controller.start()
    }

    private func stop(_ module: NotchModule) {
        switch module {
        case let module as MediaModule: module.stop()
        case let module as DownloadsModule: module.stop()
        case let module as BluetoothModule: module.stop()
        case let module as StatusModule: module.stop()
        case let module as FileTrayModule: module.stop()
        case let module as ScreenshotModule: module.stop()
        case let module as ClipboardModule: module.stop()
        default: break
        }
    }

    private func setClipboardHotKey(_ on: Bool) {
        if on, clipboardHotKey == nil {
            clipboardHotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey) { [weak self] in self?.clipboardPopup.toggle() }
        } else if !on {
            clipboardHotKey?.unregister()
            clipboardHotKey = nil
        }
    }
}
