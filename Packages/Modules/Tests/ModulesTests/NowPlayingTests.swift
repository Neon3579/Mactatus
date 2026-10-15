import Foundation
import Testing
@testable import Modules

/// mediaremote-adapter `stream --micros` 출력 형식(README v0.7.7)으로 만든 줄. 곡 정보는 지어낸 값.
@Suite("재생 정보 해석")
struct NowPlayingTests {
    let full = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","playing":true,"title":"Test Song","artist":"Test Artist","album":"Test Album","durationMicros":200000000,"elapsedTimeMicros":30000000,"timestampEpochMicros":1760000000000000,"playbackRate":1,"artworkMimeType":"image/png","artworkData":"iVBORw0KGgo="}}"#

    @Test func fullPayload() throws {
        var stream = NowPlayingStream()
        let now = try #require(try stream.apply(line: Data(full.utf8)))
        #expect(now.bundleID == "com.apple.Music")
        #expect(now.title == "Test Song")
        #expect(now.artist == "Test Artist")
        #expect(now.isPlaying)
        #expect(now.duration == 200)
        #expect(now.elapsed == 30)
        #expect(now.timestamp == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(now.artworkData == Data(base64Encoded: "iVBORw0KGgo="))
    }

    @Test func diffUpdatesOnlyChangedKeys() throws {
        var stream = NowPlayingStream()
        _ = try stream.apply(line: Data(full.utf8))
        let diff = #"{"type":"data","diff":true,"payload":{"playing":false,"elapsedTimeMicros":45000000}}"#
        let now = try #require(try stream.apply(line: Data(diff.utf8)))
        #expect(!now.isPlaying)
        #expect(now.elapsed == 45)
        #expect(now.title == "Test Song")
    }

    @Test func nullInDiffRemovesKey() throws {
        var stream = NowPlayingStream()
        _ = try stream.apply(line: Data(full.utf8))
        let diff = #"{"type":"data","diff":true,"payload":{"artist":null,"artworkData":null}}"#
        let now = try #require(try stream.apply(line: Data(diff.utf8)))
        #expect(now.artist == nil)
        #expect(now.artworkData == nil)
    }

    @Test func emptyPayloadMeansNothingPlaying() throws {
        var stream = NowPlayingStream()
        _ = try stream.apply(line: Data(full.utf8))
        #expect(try stream.apply(line: Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8)) == nil)
    }

    @Test func browserUsesParentApp() throws {
        var stream = NowPlayingStream()
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome.helper","parentApplicationBundleIdentifier":"com.google.Chrome","playing":true,"title":"Video"}}"#
        let now = try #require(try stream.apply(line: Data(line.utf8)))
        #expect(now.appBundleID == "com.google.Chrome")
        #expect(now.duration == nil)
    }

    @Test func invalidLineThrows() {
        var stream = NowPlayingStream()
        #expect(throws: (any Error).self) { try stream.apply(line: Data("not json".utf8)) }
    }

    @Test func elapsedAdvancesOnlyWhilePlaying() {
        let start = Date(timeIntervalSince1970: 1000)
        var now = NowPlaying(bundleID: "a", title: "t", isPlaying: true, duration: 100, elapsed: 10, timestamp: start, playbackRate: 1)
        #expect(now.elapsed(at: start.addingTimeInterval(5)) == 15)
        #expect(now.elapsed(at: start.addingTimeInterval(500)) == 100)
        now.isPlaying = false
        #expect(now.elapsed(at: start.addingTimeInterval(5)) == 10)
    }
}
