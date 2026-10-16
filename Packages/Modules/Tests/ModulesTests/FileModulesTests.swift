import Foundation
import Testing
@testable import Modules

@Suite("파일 트레이 규칙")
struct TrayRulesTests {
    func item(_ path: String, hoursAgo: Double = 0) -> TrayItem {
        TrayItem(id: UUID(), path: path, bookmark: nil, isCopy: false, addedAt: Date(timeIntervalSinceNow: -hoursAgo * 3600))
    }

    @Test func sameFileMovesToFront() {
        let a = item("/tmp/a.txt"), b = item("/tmp/b.txt")
        let result = TrayRules.adding([item("/tmp/a.txt")], to: [b, a])
        #expect(result.map(\.path) == ["/tmp/a.txt", "/tmp/b.txt"])
    }

    @Test func newFilesKeepDropOrder() {
        let result = TrayRules.adding([item("/tmp/1"), item("/tmp/2")], to: [item("/tmp/0")])
        #expect(result.map(\.path) == ["/tmp/1", "/tmp/2", "/tmp/0"])
    }

    @Test func expiresOnlyOldItems() {
        let old = item("/tmp/old", hoursAgo: 30), fresh = item("/tmp/fresh", hoursAgo: 2)
        #expect(TrayRules.expired([old, fresh], hours: 24, now: .now).map(\.path) == ["/tmp/old"])
        #expect(TrayRules.expired([old, fresh], hours: 0, now: .now).isEmpty)
    }
}

@Suite("클립보드 기록 규칙")
struct ClipboardRulesTests {
    @Test func skipsPasswordManagerTypes() {
        #expect(ClipboardRules.shouldSkip(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(ClipboardRules.shouldSkip(types: ["org.nspasteboard.TransientType"]))
        #expect(!ClipboardRules.shouldSkip(types: ["public.utf8-plain-text"]))
    }

    @Test func duplicateMovesToFrontAndKeepsPin() {
        let pinned = ClipboardItem(content: .text("안녕"), isPinned: true)
        let other = ClipboardItem(content: .text("다른 글"))
        let result = ClipboardRules.adding(ClipboardItem(content: .text("안녕")), to: [other, pinned], limit: 50)
        #expect(result.items.count == 2)
        #expect(result.items[0].content == .text("안녕"))
        #expect(result.items[0].isPinned)
    }

    @Test func trimsOldUnpinnedBeyondLimit() {
        let items = (0..<3).map { ClipboardItem(content: .text("글 \($0)")) } + [ClipboardItem(content: .text("고정"), isPinned: true)]
        let result = ClipboardRules.adding(ClipboardItem(content: .text("새 글")), to: items, limit: 2)
        #expect(result.items.map(\.summary) == ["새 글", "글 0", "고정"])
        #expect(result.removed.map(\.summary) == ["글 1", "글 2"])
    }

    @Test func pinnedFirstAndSearch() {
        let a = ClipboardItem(content: .text("사과")), b = ClipboardItem(content: .text("바나나"), isPinned: true)
        #expect(ClipboardRules.filtered([a, b], query: "").map(\.summary) == ["바나나", "사과"])
        #expect(ClipboardRules.filtered([a, b], query: "사").map(\.summary) == ["사과"])
    }

    @Test func summaries() {
        #expect(ClipboardItem(content: .text("\n  \n첫 줄\n둘째 줄")).summary == "첫 줄")
        #expect(ClipboardItem(content: .text("첫 줄\n둘째 줄")).summary == "첫 줄")
        #expect(ClipboardItem(content: .files(["/a/보고서.pdf", "/a/b.png"])).summary == "보고서.pdf 외 1개")
        #expect(ClipboardItem(content: .image("x.png")).summary == "이미지")
        #expect(ClipboardItem(content: .image("y.png"), sourceApp: ClipboardItem.screenshotSource).summary == "스크린샷")
    }
}
