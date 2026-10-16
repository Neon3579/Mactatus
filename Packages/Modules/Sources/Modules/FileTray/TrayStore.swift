import Foundation

/// 트레이에 담긴 파일 하나.
public struct TrayItem: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// 원본(참조) 또는 Mactatus가 보관한 복사본의 위치
    public var path: String
    /// 원본 참조일 때 파일이 옮겨져도 찾아가기 위한 북마크
    public var bookmark: Data?
    /// Mactatus가 복사해 보관하는 파일인지(트레이에서 빼거나 비우면 지운다)
    public var isCopy: Bool
    public var addedAt: Date

    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { url.lastPathComponent }
}

/// 트레이 목록 규칙(디스크와 떨어진 순수한 부분이라 테스트한다).
public enum TrayRules {
    /// 담기: 같은 파일은 다시 담지 않고 맨 앞으로 올린다.
    public static func adding(_ new: [TrayItem], to items: [TrayItem]) -> [TrayItem] {
        var result = items
        for item in new.reversed() {
            result.removeAll { $0.path == item.path }
            result.insert(item, at: 0)
        }
        return result
    }

    /// 자동 비우기: 담은 지 `hours`시간이 지난 것을 뺀다(0이면 비우지 않음).
    public static func expired(_ items: [TrayItem], hours: Int, now: Date) -> [TrayItem] {
        guard hours > 0 else { return [] }
        return items.filter { now.timeIntervalSince($0.addedAt) > Double(hours) * 3600 }
    }
}

/// 트레이 목록을 이 맥(~/Library/Application Support/Mactatus/Tray)에 저장한다.
struct TrayDisk {
    let folder: URL

    init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Mactatus/Tray")) {
        self.folder = folder
    }

    private var listURL: URL { folder.appendingPathComponent("tray.json") }
    private var filesFolder: URL { folder.appendingPathComponent("Files") }

    func load() -> [TrayItem] {
        guard let data = try? Data(contentsOf: listURL) else { return [] }
        return (try? JSONDecoder().decode([TrayItem].self, from: data)) ?? []
    }

    func save(_ items: [TrayItem]) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(items).write(to: listURL, options: .atomic)
    }

    /// 담을 항목을 만든다. 복사 모드면 보관 폴더로 복사한다.
    func makeItem(for url: URL, copy: Bool) -> TrayItem? {
        let id = UUID()
        if copy {
            let destination = filesFolder.appendingPathComponent(id.uuidString).appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                return nil
            }
            return TrayItem(id: id, path: destination.path, bookmark: nil, isCopy: true, addedAt: .now)
        }
        let bookmark = try? url.bookmarkData()
        return TrayItem(id: id, path: url.path, bookmark: bookmark, isCopy: false, addedAt: .now)
    }

    /// 원본이 옮겨졌으면 북마크로 새 위치를 찾는다. 없어졌으면 nil.
    func resolve(_ item: TrayItem) -> TrayItem? {
        if FileManager.default.fileExists(atPath: item.path) { return item }
        guard let bookmark = item.bookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        var updated = item
        updated.path = url.path
        if stale { updated.bookmark = try? url.bookmarkData() }
        return updated
    }

    /// 복사본이면 보관 폴더에서 지운다(원본은 건드리지 않는다).
    func discard(_ item: TrayItem) {
        guard item.isCopy else { return }
        try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
    }
}
