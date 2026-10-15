import Foundation

/// 지금 재생 중인 미디어.
public struct NowPlaying: Sendable, Equatable {
    /// 재생 중인 앱(브라우저 탭이면 웹 콘텐츠 프로세스일 수 있어 `parentBundleID`를 먼저 본다)
    public var bundleID: String
    public var parentBundleID: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var isPlaying: Bool
    public var duration: TimeInterval?
    /// `timestamp` 시각의 경과 시간
    public var elapsed: TimeInterval?
    public var timestamp: Date?
    public var playbackRate: Double?
    public var artworkData: Data?

    public init(bundleID: String, parentBundleID: String? = nil, title: String, artist: String? = nil, album: String? = nil,
                isPlaying: Bool, duration: TimeInterval? = nil, elapsed: TimeInterval? = nil, timestamp: Date? = nil,
                playbackRate: Double? = nil, artworkData: Data? = nil) {
        self.bundleID = bundleID
        self.parentBundleID = parentBundleID
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.playbackRate = playbackRate
        self.artworkData = artworkData
    }

    /// 앱 아이콘·이름을 찾을 번들 ID
    public var appBundleID: String { parentBundleID ?? bundleID }

    /// `date` 시각의 경과 시간 추정(재생 중이면 `timestamp` 이후 흐른 시간만큼 더한다)
    public func elapsed(at date: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        guard isPlaying, let timestamp else { return elapsed }
        let rate = (playbackRate ?? 1) > 0 ? (playbackRate ?? 1) : 1
        let value = elapsed + max(date.timeIntervalSince(timestamp), 0) * rate
        return duration.map { min(value, $0) } ?? value
    }
}

/// mediaremote-adapter `stream --micros` 출력 해석.
///
/// 한 줄은 `{"type":"data","diff":Bool,"payload":{...}}`. `diff`가 false면 payload가 지금 상태 전부이고,
/// true면 바뀐 키만 온다(값이 null인 키는 사라진 것). payload가 비어 있으면 재생 중인 것이 없다.
public struct NowPlayingStream: Sendable {
    public enum ParseError: Error { case notData }

    private var state: [String: JSONValue] = [:]

    public init() {}

    /// 한 줄을 반영하고 지금 재생 정보를 돌려준다(재생 중인 것이 없으면 nil).
    public mutating func apply(line: Data) throws -> NowPlaying? {
        let message = try JSONDecoder().decode(Message.self, from: line)
        guard message.type == "data" else { throw ParseError.notData }
        if message.diff != true { state = [:] }
        for (key, value) in message.payload {
            if case .null = value { state[key] = nil } else { state[key] = value }
        }
        return Self.nowPlaying(from: state)
    }

    static func nowPlaying(from state: [String: JSONValue]) -> NowPlaying? {
        guard let bundleID = state["bundleIdentifier"]?.string, let title = state["title"]?.string,
              let isPlaying = state["playing"]?.bool else { return nil }
        let micros = { (key: String) in state[key]?.number.map { $0 / 1_000_000 } }
        return NowPlaying(
            bundleID: bundleID,
            parentBundleID: state["parentApplicationBundleIdentifier"]?.string,
            title: title,
            artist: state["artist"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            album: state["album"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            isPlaying: isPlaying,
            duration: micros("durationMicros").flatMap { $0 > 0 ? $0 : nil },
            elapsed: micros("elapsedTimeMicros"),
            timestamp: micros("timestampEpochMicros").map { Date(timeIntervalSince1970: $0) },
            playbackRate: state["playbackRate"]?.number,
            artworkData: state["artworkData"]?.string.flatMap { Data(base64Encoded: $0) })
    }

    private struct Message: Decodable {
        let type: String
        let diff: Bool?
        let payload: [String: JSONValue]
    }
}

/// 아무 JSON 값.
enum JSONValue: Sendable, Equatable, Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = .other }
    }

    var string: String? { if case .string(let value) = self { value } else { nil } }
    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
}
