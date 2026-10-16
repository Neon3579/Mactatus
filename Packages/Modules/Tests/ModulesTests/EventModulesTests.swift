import Foundation
import Testing
@testable import Modules

@Suite("다운로드 파일 이름")
struct DownloadNamesTests {
    @Test func partialExtensionsAreRemoved() {
        let folder = URL(fileURLWithPath: "/Users/test/Downloads")
        #expect(DownloadNames.finalURL(for: folder.appendingPathComponent("a.zip.download")).lastPathComponent == "a.zip")
        #expect(DownloadNames.finalURL(for: folder.appendingPathComponent("b.dmg.crdownload")).lastPathComponent == "b.dmg")
        #expect(DownloadNames.finalURL(for: folder.appendingPathComponent("c.pdf.part")).lastPathComponent == "c.pdf")
    }

    @Test func finishedFilesStayTheSame() {
        let url = URL(fileURLWithPath: "/Users/test/Downloads/report.pdf")
        #expect(!DownloadNames.isPartial(url))
        #expect(DownloadNames.finalURL(for: url) == url)
    }

    @Test func statusText() {
        let item = DownloadItem(id: "x", name: "a.zip", fraction: 0.42, secondsRemaining: 150)
        #expect(DownloadsExpandedView.status(item) == "42% · 2분 남음")
        let unknown = DownloadItem(id: "y", name: "b.zip", fraction: nil, secondsRemaining: nil)
        #expect(DownloadsExpandedView.status(unknown) == "")
    }
}

@Suite("블루투스 기기")
struct BluetoothDeviceTests {
    @Test func airPodsUseLowerEarbud() {
        let levels = BatteryLevels(left: 80, right: 65, caseLevel: 40)
        #expect(levels.summary == 65)
        #expect(levels.detail == "왼쪽 80% · 오른쪽 65% · 케이스 40%")
    }

    @Test func zeroMeansUnknown() {
        let levels = BatteryLevels(left: 0, right: 90, caseLevel: 0)
        #expect(levels.left == nil)
        #expect(levels.summary == 90)
        #expect(levels.detail == "오른쪽 90%")
        #expect(BatteryLevels().summary == nil)
        #expect(BatteryLevels().detail == nil)
    }

    @Test func shortNameDropsOwner() {
        func name(_ text: String) -> String { BluetoothDeviceInfo(id: "x", name: text, symbol: "", battery: BatteryLevels()).shortName }
        #expect(name("홍길동의 AirPods Pro") == "AirPods Pro")
        #expect(name("Kim's AirPods") == "AirPods")
        #expect(name("Magic Keyboard") == "Magic Keyboard")
    }

    @Test func singleBatteryDevice() {
        #expect(BatteryLevels(single: 55).summary == 55)
        #expect(BatteryLevels(single: 55).detail == "55%")
    }

    @Test func symbolsByNameAndClass() {
        #expect(BluetoothSymbols.symbol(name: "테스트의 AirPods Pro", majorClass: 0x04, minorClass: 0x06) == "airpodspro")
        #expect(BluetoothSymbols.symbol(name: "AirPods Max", majorClass: 0x04, minorClass: 0x06) == "airpodsmax")
        #expect(BluetoothSymbols.symbol(name: "Sony WH-1000XM5", majorClass: 0x04, minorClass: 0x06) == "headphones")
        #expect(BluetoothSymbols.symbol(name: "Speaker", majorClass: 0x04, minorClass: 0x05) == "hifispeaker")
        #expect(BluetoothSymbols.symbol(name: "Keychron K2", majorClass: 0x05, minorClass: 0x10) == "keyboard")
        #expect(BluetoothSymbols.symbol(name: "Magic Trackpad", majorClass: 0x05, minorClass: 0x20) == "hand.point.up.left")
    }
}
