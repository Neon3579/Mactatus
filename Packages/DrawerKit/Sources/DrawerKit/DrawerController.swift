import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// 메뉴바 서랍.
///
/// - Windows처럼 다른 앱 아이콘은 기본으로 서랍에 넣고, 메뉴바에는 시스템 아이콘·입력 소스·
///   Mactatus 아이콘과 사용자가 꺼낸 아이콘만 둔다.
/// - 서랍 아이콘은 ⌄ 왼쪽에 모으고, ⌄ 버튼 왼쪽에 빈 공간을 붙여 macOS 기본 « 안으로 보낸다
///   (macOS 27에는 아이콘을 숨길 곳이 « 밖에 없음).
/// - 서랍 패널은 숨겨진 아이콘을 보여주고, 누르면 그 아이콘을 손쉬운 사용으로 눌러 원래 메뉴를 연다.
/// - 서랍에 넣기·꺼내기는 사람이 하듯 ⌘-끌기로 옮긴다.
@MainActor
@Observable
public final class DrawerController {
    public static let toggleLabel = "Mactatus 서랍"

    public private(set) var scan: MenuBarScan?
    public private(set) var isTrusted = AXIsProcessTrusted()
    /// 넣기·꺼내기 중
    public private(set) var isBusy = false
    /// 사용자에게 보여줄 안내(꺼내기 실패 등)
    public private(set) var notice: String?
    public private(set) var spacer: CGFloat = 0
    /// 편집 모드(메뉴바 위 덮개로 ⌘ 없이 끌기)
    public private(set) var isEditing = false

    /// 서랍 패널 내용(앱이 SwiftUI 화면을 넘겨준다)
    @ObservationIgnored public var makePanelContent: (() -> AnyView)?
    /// Mactatus의 다른 메뉴바 아이콘(AI·시스템)이 ⌄ 왼쪽(서랍 쪽)에 있을 때 부른다.
    /// 숨은 아이콘은 끌 수 없으므로 앱이 그 아이콘을 ⌄ 오른쪽 위치값으로 다시 만든다.
    @ObservationIgnored public var onOwnItemsLeftOfToggle: (() -> Void)?
    @ObservationIgnored private var ownRelocations = 0
    /// 정리할 아이콘이 있는데 ⌄까지 « 로 숨었을 때, 앱이 자기 아이콘(AI·시스템)을 잠깐 빼서(true) 자리를 만들고
    /// 정리가 끝나면 되돌린다(false). 숨은 ⌄는 끌 목표로 쓸 수 없어서.
    @ObservationIgnored public var onMakeRoom: ((Bool) -> Void)?
    @ObservationIgnored private var madeRoomAt: Date?

    @ObservationIgnored private let scanner = MenuBarScanner(toggleLabel: DrawerController.toggleLabel)
    @ObservationIgnored private let icons = MenuBarIcons()
    @ObservationIgnored private let panel = MenuBarPanel()
    @ObservationIgnored private let overlay = EditOverlayHost()
    @ObservationIgnored private let ghost = DragGhost()
    @ObservationIgnored private var statusItem: NSStatusItem?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var sleeper: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let defaults = UserDefaults.standard

    public init() {}

    // MARK: - 화면이 쓰는 값

    public var isPanelVisible: Bool { panel.isVisible }

    public func icon(for item: MenuBarItem) -> NSImage? { icons.image(for: item) }

    // MARK: - 켜기·끄기

    public func start() {
        guard statusItem == nil else { return }
        installToggle()
        observeApps()
        // 로그인·재실행 때는 앱 아이콘이 예전 자리로 돌아와 있을 수 있어 한 번 정리한다(옮길 게 없으면 커서를 쓰지 않음)
        needsReconcile = true
        reconcileAttempts = 0
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                isTrusted = AXIsProcessTrusted()
                if isTrusted { await refresh() }
                // 정리 중에는 빨리 끝내려고 자주 훑는다
                let interval: Double = isTrusted && needsReconcile ? 1 : panel.isVisible ? 1.5 : (isTrusted ? 6 : 3)
                let wait = Task { _ = try? await Task.sleep(for: .seconds(interval)) }
                sleeper = wait
                await wait.value
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        panel.close()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        spacer = 0
    }

    /// 손쉬운 사용 권한을 묻고 시스템 설정을 연다.
    public func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 동작

    public func togglePanel() {
        if panel.isVisible { closePanel(); return }
        // ⌄를 눌러 닫는 경우: 바깥 클릭 처리가 방금 닫았으니 다시 열지 않는다
        if panel.justClosedByOutsideClick { return }
        showPanel()
    }

    private func showPanel() {
        guard let content = makePanelContent?() else { return }
        notice = nil
        panel.keepOpen = isEditing
        panel.onEscape = isEditing ? { [weak self] in self?.stopEditing() } : nil
        let anchor = scan?.toggle.map(\.maxX) ?? NSEvent.mouseLocation.x
        panel.show(content: content, anchorX: anchor) { [weak self] in
            self?.sleeper?.cancel()
        }
        sleeper?.cancel() // 바로 다시 훑기
    }

    public func closePanel() {
        if isEditing { stopEditing() }
        panel.close()
    }

    // MARK: - 편집 모드

    public func startEditing() {
        guard isTrusted, !isEditing else { return }
        isEditing = true
        panel.close()
        showPanel()
        overlay.show(controller: self)
    }

    public func stopEditing() {
        guard isEditing else { return }
        isEditing = false
        overlay.close()
        ghost.hide()
        panel.keepOpen = false
        panel.onEscape = nil
        panel.close()
    }

    /// 편집 덮개가 덮는 영역의 왼쪽 끝(« 오른쪽 또는 노치 오른쪽, CG x).
    public var statusAreaLeft: CGFloat {
        let notch = NSScreen.screens.first?.auxiliaryTopRightArea?.minX ?? 0
        return max(scan?.chevron?.maxX ?? notch, notch)
    }

    // MARK: - 끌기(편집 모드·서랍 타일 공통)

    func beginGhost(for item: MenuBarItem?) {
        ghost.show(image: item.flatMap { icons.image(for: $0) }
            ?? NSImage(systemSymbolName: "chevron.down.circle.fill", accessibilityDescription: nil))
        ghost.move(to: NSEvent.mouseLocation)
    }

    func moveGhost(to point: NSPoint) { ghost.move(to: point) }
    func endGhost() { ghost.hide() }

    /// Cocoa 화면 좌표가 메뉴바 줄 위인지.
    func isOverMenuBar(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let height = screen.frame.maxY - screen.visibleFrame.maxY
        return point.y >= screen.frame.maxY - height && point.x >= statusAreaLeft
    }

    func isOverPanel(_ point: NSPoint) -> Bool { panel.frame?.contains(point) ?? false }

    /// 서랍 패널의 타일을 끄는 중.
    public func tileDragChanged(_ item: MenuBarItem) {
        beginGhost(for: item)
        moveGhost(to: NSEvent.mouseLocation)
    }

    /// 서랍 패널의 타일을 놓음: 메뉴바 위면 그 자리로 꺼낸다.
    public func tileDragEnded(_ item: MenuBarItem) {
        endGhost()
        let point = NSEvent.mouseLocation
        guard isOverMenuBar(point) else { return }
        Task { await moveToMenuBar(item, x: point.x) }
    }

    /// 아이콘을 눌러 원래 메뉴를 연다(숨겨져 있어도 된다).
    public func open(_ item: MenuBarItem) {
        closePanel()
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            if await !scanner.press(item) { notice = "\(item.displayName)을(를) 열지 못했어요." }
        }
    }

    // MARK: - 메뉴바에 둘 아이콘(고정)과 서랍

    /// 시스템 아이콘 외에 처음부터 메뉴바에 두는 Apple 아이콘(입력 소스).
    /// Spotlight(`com.apple.campo`)는 ⌘Space로 여는 일이 많고 노치 오른쪽 자리가 좁아 서랍에 둔다.
    static let defaultPinnedBundles: Set<String> = ["com.apple.TextInputMenuAgent"]

    private var userPinned: Set<String> {
        get { Set(defaults.stringArray(forKey: "drawer.pinned") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "drawer.pinned") }
    }

    private var userDrawer: Set<String> {
        get { Set(defaults.stringArray(forKey: "drawer.inDrawer") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "drawer.inDrawer") }
    }

    /// 메뉴바에 둘 아이콘인지. 그 밖의 아이콘은 모두 서랍(Windows 11처럼 새 아이콘도 서랍으로).
    public func isPinned(_ item: MenuBarItem) -> Bool {
        if item.isSystem || item.isOwn { return true }
        if userDrawer.contains(item.key) { return false }
        if userPinned.contains(item.key) { return true }
        return item.bundleID.map(Self.defaultPinnedBundles.contains) ?? false
    }

    /// 서랍에 든 아이콘(숨겨졌는지와 상관없이).
    public var drawerItems: [MenuBarItem] {
        (scan?.items ?? []).filter { !$0.isOwn && !isPinned($0) }
    }

    /// 메뉴바에 두기로 한 아이콘(시스템 아이콘 제외).
    public var menuBarItems: [MenuBarItem] {
        (scan?.items ?? []).filter { !$0.isOwn && !$0.isSystem && isPinned($0) }
    }

    /// 서랍에 넣는다: 메뉴바 목록에서 빼고 배치를 다시 맞춘다.
    public func putInDrawer(_ item: MenuBarItem) async {
        guard !item.isSystem, !item.isOwn else { return }
        userPinned.remove(item.key)
        userDrawer.insert(item.key)
        await reconcileNow()
    }

    /// 메뉴바로 꺼낸다(⌄ 바로 오른쪽).
    public func takeOut(_ item: MenuBarItem) async {
        await moveToMenuBar(item, x: nil)
    }

    /// 메뉴바로 꺼내 x 위치(⌄ 오른쪽)에 둔다. 숨겨진 아이콘은 끌 수 없어서 빈 공간을 잠깐 없애 보이게 한 뒤 옮긴다.
    public func moveToMenuBar(_ item: MenuBarItem, x: CGFloat?) async {
        guard !isBusy else { return }
        if let x, let toggle = scan?.toggle, x <= toggle.minX {
            await putInDrawer(item)
            return
        }
        userDrawer.remove(item.key)
        userPinned.insert(item.key)
        isBusy = true
        defer { isBusy = false }
        guard let current = await revealIfHidden(item), let toggle = scan?.toggle, !(scan?.toggleHidden ?? true) else {
            notice = "메뉴바에 자리가 없어 \(item.displayName)을(를) 보이게 하지 못했어요. 다른 아이콘을 서랍에 넣어 자리를 만든 뒤 다시 해 주세요."
            return
        }
        let target = max(x ?? (toggle.maxX + 2), toggle.maxX + 2)
        await drag(from: center(current), to: CGPoint(x: target, y: toggle.midY))
    }

    /// 편집 모드에서 아이콘(nil이면 ⌄)을 x 위치로 옮긴다. ⌄ 왼쪽에 놓으면 서랍, 오른쪽이면 메뉴바.
    public func move(_ item: MenuBarItem?, toX x: CGFloat) async {
        guard !isBusy, let toggle = scan?.toggle else { return }
        guard let item else {
            // ⌄ 자체를 옮김: 오른쪽 끝(⌄ 그림)을 잡아야 빈 공간이 아닌 버튼을 끈다
            isBusy = true
            defer { isBusy = false }
            await drag(from: CGPoint(x: toggle.maxX - 10, y: toggle.midY), to: CGPoint(x: x, y: toggle.midY))
            return
        }
        if x <= toggle.minX {
            await putInDrawer(item)
            return
        }
        userDrawer.remove(item.key)
        userPinned.insert(item.key)
        guard let current = scan?.items.first(where: { $0.key == item.key && !$0.isHidden }),
              !(current.frame.minX...current.frame.maxX).contains(x) else { return }
        isBusy = true
        defer { isBusy = false }
        await drag(from: center(current), to: CGPoint(x: x, y: current.frame.midY))
    }

    /// 다른 앱 아이콘을 모두 다시 서랍으로(사용자가 꺼낸 것은 그대로) 정리한다.
    public func rearrange() {
        needsReconcile = true
        reconcileAttempts = 0
        sleeper?.cancel()
    }

    // MARK: - 안쪽: 배치 맞추기

    /// ⌘-끌기(커서가 움직임)가 필요한 정리를 해도 되는 때인지. 처음 켤 때와 사용자가 넣기·꺼내기를 했을 때만 켠다.
    private var needsReconcile: Bool {
        get { defaults.object(forKey: "drawer.needsReconcile") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "drawer.needsReconcile") }
    }
    @ObservationIgnored private var reconcileAttempts = 0
    @ObservationIgnored private var spacerCeiling: (value: CGFloat, signature: String)?
    @ObservationIgnored private var lastLayoutNote = ""

    private func center(_ item: MenuBarItem) -> CGPoint { CGPoint(x: item.frame.midX, y: item.frame.midY) }

    /// 사용자가 2초 안에 키보드·마우스를 썼는지. ⌘-끌기 중 누르고 있는 ⌘와 타자가 겹치면 단축키가 눌리므로 정리는 쉬는 틈에만 한다.
    private var userIsActive: Bool {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) < 2
    }

    /// ⌘-끌기 한 번. 편집 중이면 덮개를 잠깐 치웠다가 다시 덮는다.
    private func drag(from: CGPoint, to: CGPoint) async {
        overlay.suspend()
        ghost.hide()
        DrawerDebug.log("옮기기: x \(Int(from.x)) → \(Int(to.x))")
        await EventSynth.commandDrag(from: from, to: to)
        try? await Task.sleep(for: .milliseconds(800))
        scan = await scanner.scan()
        if isEditing { overlay.resume(controller: self) }
    }

    /// 숨겨진 아이콘이면 빈 공간을 잠깐 없애 보이게 한다. 보이게 된(또는 원래 보이던) 최신 모습을 돌려준다.
    private func revealIfHidden(_ item: MenuBarItem) async -> MenuBarItem? {
        if let current = scan?.items.first(where: { $0.key == item.key }), !current.isHidden { return current }
        apply(spacer: 0)
        try? await Task.sleep(for: .milliseconds(1200))
        let fresh = await scanner.scan()
        scan = fresh
        return fresh.items.first(where: { $0.key == item.key && !$0.isHidden })
    }

    private func finishReconcile(_ message: String?) {
        needsReconcile = false
        if let message { DrawerDebug.log(message) }
        if madeRoomAt != nil {
            madeRoomAt = nil
            onMakeRoom?(false)
        }
    }

    private func reconcileNow() async {
        needsReconcile = true
        reconcileAttempts = 0
        await refresh()
    }

    /// 아이콘 구성과 앞에 있는 앱이 같으면 같은 배치로 본다(앞 앱의 메뉴 길이에 따라 남는 자리가 달라짐).
    private func layoutSignature(_ scan: MenuBarScan) -> String {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        return "\(front)|" + scan.items.map(\.key).sorted().joined(separator: ",")
    }

    /// 한 번 훑고 배치를 맞춘다.
    /// 1) 정리가 필요할 때(처음·넣기·꺼내기 직후)만, 한 번에 아이콘 하나씩 ⌘-끌기로 옮긴다:
    ///    서랍 아이콘이 ⌄ 오른쪽에 보이면 왼쪽으로, 메뉴바 아이콘이 ⌄ 왼쪽에 있으면 오른쪽으로.
    /// 2) 평소에는 ⌄ 왼쪽 빈 공간 폭만 맞춘다: 서랍 아이콘이 보이면 그 폭만큼 넓혀 « 로 보낸다.
    private func refresh() async {
        var current = await scanner.scan()
        scan = current
        guard !isBusy else { return }

        if let toggle = current.toggle, !current.toggleHidden, ownRelocations < 2, let relocate = onOwnItemsLeftOfToggle,
           current.items.contains(where: { $0.isOwn && $0.frame.midX < toggle.minX }) {
            ownRelocations += 1
            let own = current.items.filter(\.isOwn).map { "\($0.displayName) x\(Int($0.frame.minX))\($0.isHidden ? "(숨김)" : "")" }
            DrawerDebug.log("Mactatus 아이콘이 ⌄(x\(Int(toggle.minX))) 왼쪽에 있어 오른쪽에 다시 만듦(\(ownRelocations)번째): \(own.joined(separator: ", "))")
            relocate()
            return
        }

        if needsReconcile, let madeRoomAt, Date().timeIntervalSince(madeRoomAt) > 30 {
            finishReconcile("자리를 만들어도 정리를 끝내지 못해 그만둠")
        } else if needsReconcile, current.toggleHidden, madeRoomAt == nil, let makeRoom = onMakeRoom, !userIsActive,
                  current.items.contains(where: { !$0.isHidden && !isPinned($0) }) {
            madeRoomAt = Date()
            DrawerDebug.log("⌄가 숨어 있어 Mactatus 아이콘을 잠깐 빼고 정리")
            makeRoom(true)
            return
        }

        if needsReconcile, !current.toggleHidden, let toggle = current.toggle {
            if userIsActive { return }
            // 아이콘 하나에 한 번 끌기가 보통이라 아이콘 수만큼(+여유) 해 보고 그만둔다
            if reconcileAttempts >= current.items.filter({ !$0.isSystem }).count + 4 {
                finishReconcile("정리 중단(시도 횟수 초과)")
            } else if let stray = current.items.first(where: { !$0.isHidden && !isPinned($0) && $0.frame.midX > toggle.maxX }) {
                reconcileAttempts += 1
                isBusy = true
                await drag(from: center(stray), to: CGPoint(x: toggle.minX + 2, y: toggle.midY))
                isBusy = false
                return
            } else if let pinned = current.items.first(where: { !$0.isHidden && !$0.isSystem && !$0.isOwn && isPinned($0) && $0.frame.midX < toggle.minX }) {
                reconcileAttempts += 1
                isBusy = true
                await drag(from: center(pinned), to: CGPoint(x: toggle.maxX + 2, y: toggle.midY))
                isBusy = false
                return
            } else if current.items.contains(where: { $0.isHidden && !$0.isSystem && !$0.isOwn && isPinned($0) }), spacer > 0 {
                // 메뉴바에 둘 아이콘이 « 안에 있다 → 빈 공간을 없애 보이게 한 뒤 다음 차례에 오른쪽으로 옮긴다
                reconcileAttempts += 1
                DrawerDebug.log("메뉴바 아이콘을 보이게 하려고 빈 공간을 잠깐 없앰")
                apply(spacer: 0)
                return
            } else {
                finishReconcile(reconcileAttempts > 0 ? "정리 끝" : nil)
            }
            current = scan ?? current
        }

        let signature = layoutSignature(current)
        if spacerCeiling?.signature != signature { spacerCeiling = nil }
        if current.toggleHidden, spacer > 0 { spacerCeiling = (max(spacer - 8, 0), signature) }
        let visibleDrawer = current.items.filter { !$0.isHidden && !isPinned($0) }
        var next = DrawerLayout.nextSpacer(
            current: spacer,
            toggleVisible: !current.toggleHidden,
            visibleDrawerWidth: visibleDrawer.reduce(0) { $0 + $1.frame.width },
            hasDrawerItems: current.items.contains { !isPinned($0) })
        if let ceiling = spacerCeiling?.value { next = min(next, ceiling) }
        noteLayout(current)
        if next != spacer {
            DrawerDebug.log("빈 공간 \(Int(spacer)) → \(Int(next)) (⌄=\(current.toggle.map { "\(Int($0.minX))" } ?? "숨김"), 보이는 서랍 아이콘 \(visibleDrawer.count)개, 상한=\(spacerCeiling.map { "\(Int($0.value))" } ?? "-"))")
            apply(spacer: next)
            try? await Task.sleep(for: .milliseconds(600))
            scan = await scanner.scan()
        }
    }

    /// 아이콘마다 노치 왼쪽·오른쪽·숨김 중 어디 있는지가 바뀔 때만 배치를 한 줄 남긴다(원인 찾기용).
    private func noteLayout(_ scan: MenuBarScan) {
        let screen = NSScreen.screens.first
        let notchLeft = screen?.auxiliaryTopLeftArea?.maxX ?? .greatestFiniteMagnitude
        func place(_ frame: CGRect, hidden: Bool) -> String {
            hidden ? "숨김" : frame.minX < notchLeft ? "노치왼쪽" : "오른쪽"
        }
        var coarse: [String] = []
        var detail: [String] = []
        for item in scan.items {
            let kind = item.isSystem ? "시스템" : item.isOwn ? "Mactatus" : isPinned(item) ? "메뉴바" : "서랍"
            let where_ = place(item.frame, hidden: item.isHidden)
            if !item.isSystem { coarse.append("\(item.key)=\(where_)") }
            detail.append("\(item.displayName)[\(kind)] \(where_) x\(Int(item.frame.minX)) w\(Int(item.frame.width))")
        }
        let toggleWhere = scan.toggle.map { place($0, hidden: scan.toggleHidden) } ?? "없음"
        coarse.append("toggle=\(toggleWhere)")
        let note = coarse.joined(separator: ",")
        guard note != lastLayoutNote else { return }
        lastLayoutNote = note
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        DrawerDebug.log("배치: 앞 앱 \(front) 메뉴 끝 x\(scan.menuMaxX.map { "\(Int($0))" } ?? "?"), "
            + "노치 \(Int(notchLeft))~\(Int(screen?.auxiliaryTopRightArea?.minX ?? 0)), "
            + "« \(scan.chevron.map { "x\(Int($0.minX)) w\(Int($0.width))" } ?? "없음"), "
            + "⌄ \(toggleWhere) \(scan.toggle.map { "x\(Int($0.minX)) w\(Int($0.width))" } ?? ""), 빈 공간 \(Int(spacer))\n    "
            + detail.joined(separator: "\n    "))
    }

    // MARK: - ⌄ 버튼

    private func installToggle() {
        // 처음 만들 때만 대략 보이는 자리에 둔다(값이 클수록 왼쪽). 이후 위치는 macOS가 기억한다
        if defaults.object(forKey: "NSStatusItem Preferred Position mactatus.drawer") == nil {
            defaults.set(300.0, forKey: "NSStatusItem Preferred Position mactatus.drawer")
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "mactatus.drawer"
        item.behavior = []
        if let button = item.button {
            button.setAccessibilityLabel(Self.toggleLabel)
            button.target = ToggleTarget.shared
            button.action = #selector(ToggleTarget.clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            ToggleTarget.shared.controller = self
            button.toolTip = "메뉴바 서랍"
        }
        statusItem = item
        apply(spacer: 0)
    }

    private func apply(spacer value: CGFloat) {
        spacer = value
        statusItem?.button?.image = ToggleImage.make(spacer: value)
    }

    fileprivate func handleClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu(from: sender)
            return
        }
        // 빈 공간 부분을 누르면 무시한다
        if let event = NSApp.currentEvent {
            let point = sender.convert(event.locationInWindow, from: nil)
            if point.x < sender.bounds.width - 30 { return }
        }
        togglePanel()
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let edit = NSMenuItem(title: isEditing ? "편집 끝내기" : "메뉴 막대 편집…",
                              action: #selector(ToggleTarget.toggleEditing(_:)), keyEquivalent: "")
        edit.target = ToggleTarget.shared
        edit.isEnabled = isTrusted
        menu.addItem(edit)
        let tidy = NSMenuItem(title: "다른 앱 아이콘 모두 서랍으로", action: #selector(ToggleTarget.rearrange(_:)), keyEquivalent: "")
        tidy.target = ToggleTarget.shared
        tidy.isEnabled = isTrusted
        menu.addItem(tidy)
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.maxX - 20, y: button.bounds.minY - 4), in: button)
    }

    fileprivate func toggleEditingFromMenu() {
        isEditing ? stopEditing() : startEditing()
    }

    private func observeApps() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // 다시 켜진 앱의 아이콘은 macOS가 기억하는 예전 자리(⌄ 오른쪽일 수 있음)로 돌아오므로 정리를 다시 켠다
                    if name == NSWorkspace.didLaunchApplicationNotification {
                        self.needsReconcile = true
                        self.reconcileAttempts = 0
                    }
                    Task {
                        if let pid { await self.scanner.forget(pid: pid) }
                        try? await Task.sleep(for: .seconds(1.5))
                        self.sleeper?.cancel()
                    }
                }
            })
        }
        // 앞에 있는 앱이 바뀌면 노치 왼쪽에 남는 자리가 달라지므로 바로 다시 맞춘다
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleeper?.cancel() }
        })
    }
}

/// NSStatusBarButton의 target(약한 참조로 컨트롤러에 넘긴다).
@MainActor
private final class ToggleTarget: NSObject {
    static let shared = ToggleTarget()
    weak var controller: DrawerController?

    @objc func clicked(_ sender: NSStatusBarButton) {
        controller?.handleClick(sender)
    }

    @objc func toggleEditing(_ sender: Any?) {
        controller?.toggleEditingFromMenu()
    }

    @objc func rearrange(_ sender: Any?) {
        controller?.rearrange()
    }
}

/// ⌄ 버튼 그림: 왼쪽에 빈 공간, 오른쪽 끝에 ⌄.
enum ToggleImage {
    static func make(spacer: CGFloat) -> NSImage {
        let chevronWidth: CGFloat = 16
        let size = NSSize(width: spacer + chevronWidth, height: 18)
        let symbol = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "메뉴바 서랍")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        let image = NSImage(size: size, flipped: false) { rect in
            guard let symbol else { return true }
            let s = symbol.size
            symbol.draw(in: NSRect(x: rect.maxX - chevronWidth + (chevronWidth - s.width) / 2, y: (rect.height - s.height) / 2,
                                   width: s.width, height: s.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}


/// 서랍이 아이콘을 옮기거나 빈 공간을 바꾼 기록: ~/Library/Logs/Mactatus/drawer.log (1MB 넘으면 새로 시작)
enum DrawerDebug {
    static func log(_ message: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Mactatus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("drawer.log")
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 1_000_000 {
            try? FileManager.default.removeItem(at: url)
        }
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

