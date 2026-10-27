import Foundation
import Darwin

// Standalone assertions: runs with Apple Command Line Tools, without Xcode/XCTest.
class XCTestCase {}
func XCTAssertTrue(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { if !value() { fatalError("Assertion failed: \(message)", file: file, line: line) } }
func XCTAssertFalse(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(!value(), message, file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { XCTAssertTrue(a == b, "\(a) != \(b)") }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double) { XCTAssertTrue(abs(a - b) <= accuracy) }
func XCTAssertLessThan(_ a: Double, _ b: Double) { XCTAssertTrue(a < b) }
func XCTAssertNotNil<T>(_ value: T?) { XCTAssertTrue(value != nil) }
func XCTAssertNil<T>(_ value: T?) { XCTAssertTrue(value == nil) }
func XCTAssertNoThrow<T>(_ value: @autoclosure () throws -> T) { do { _ = try value() } catch { fatalError("Unexpected error: \(error)") } }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, _ message: String = "") { do { _ = try value(); fatalError("Expected error: \(message)") } catch {} }
func XCTFail(_ message: String) { fatalError(message) }
func XCTUnwrap<T>(_ value: T?, _ message: String = "") throws -> T { guard let value else { throw ResonanceError.message("Unwrap failed: \(message)") }; return value }

final class ResonanceTests: XCTestCase {
    func testValidLinksAndSpotifyURI() throws {
        let url = try LinkValidator.normalized(" spotify:track:6OmhkSOpvYBokMKQxpIGx2\n", for: .spotify)
        XCTAssertEqual(url.absoluteString, "https://open.spotify.com/track/6OmhkSOpvYBokMKQxpIGx2")
        let parts = try LinkValidator.spotifyParts(URL(string: "https://open.spotify.com/intl-it/album/4aawyAB9vmqN3uQ7FjRGTy?si=abc")!)
        XCTAssertEqual(parts.0, "album")
        for link in ["https://youtu.be/BaW_jenozKc", "https://www.youtube.com/watch?v=BaW_jenozKc", "https://music.youtube.com/playlist?list=PL123", "https://youtube.com/shorts/abc"] {
            XCTAssertNoThrow(try LinkValidator.normalized(link, for: .youtube))
        }
    }

    func testRejectsForeignHostsAndNonMediaLinks() {
        for link in ["file:///etc/passwd", "http://youtube.com/watch?v=x", "https://youtube.com.evil.test/watch?v=x", "https://youtube.com@evil.test/watch?v=x", "https://www.youtube.com/@channel", "https://youtube.com/watch", "https://youtube.com:443/watch?v=x", "ytsearch1:music"] {
            XCTAssertThrowsError(try LinkValidator.normalized(link, for: .youtube), link)
        }
        for link in ["https://evil.test/track/6OmhkSOpvYBokMKQxpIGx2", "https://open.spotify.com/artist/6OmhkSOpvYBokMKQxpIGx2", "spotify:track:bad"] {
            XCTAssertThrowsError(try LinkValidator.normalized(link, for: .spotify))
        }
    }

    func testSpotifyCollectionParserAndPartialWarning() throws {
        let html = #"<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":{"entity":{"title":"Example album","subtitle":"Test artist","trackList":[{"uri":"spotify:track:6OmhkSOpvYBokMKQxpIGx2","title":"Example song","subtitle":"Test artist","duration":85400},{"uri":"spotify:local:skip","title":"Local file"}]}}}}}}</script>"#
        let result = try SpotifyResolver.parse(html, kind: "album")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].duration ?? 0, 85.4, accuracy: 0.01)
        XCTAssertEqual(result.items[0].album, "Example album")
        XCTAssertEqual(result.items[0].position, 1)
        XCTAssertTrue(result.items[0].spotify)
        XCTAssertNotNil(result.notice)
        XCTAssertThrowsError(try SpotifyResolver.parse("<html>Access denied</html>", kind: "playlist"))
    }

    func testSpotifySingleTrackArtists() throws {
        let html = #"<script id="__NEXT_DATA__">{"props":{"pageProps":{"state":{"data":{"entity":{"uri":"spotify:track:6OmhkSOpvYBokMKQxpIGx2","title":"Test song","artists":[{"name":"A"},{"name":"B"}],"duration":1000}}}}}}</script>"#
        let result = try SpotifyResolver.parse(html, kind: "track")
        XCTAssertEqual(result.items[0].artist, "A, B")
        XCTAssertNil(result.notice)
    }

    func testDownloadOptionsConstrainVideoAndDoNotFakeLosslessBitrate() {
        let item = MediaItem(id: "x", title: "Title", artist: "Artist", url: "https://youtu.be/x")
        var options = ExportOptions(destination: URL(fileURLWithPath: "/tmp/with spaces"))
        options.format = .flac
        var args = Engine.downloadArguments(item: item, source: item.url, options: options, directory: options.destination)
        XCTAssertFalse(args.contains("--audio-quality"))
        options.kind = .video; options.format = .mp4; options.height = "720"
        args = Engine.downloadArguments(item: item, source: item.url, options: options, directory: options.destination)
        let selection = args[args.firstIndex(of: "--format")! + 1]
        XCTAssertTrue(selection.contains("height<=720"))
        XCTAssertTrue(selection.contains("vcodec^=avc1"))
        XCTAssertEqual(args.suffix(2), ["--", item.url])
        XCTAssertEqual(Engine.safeFilename("../Artist:Song/Title"), ".._Artist_Song_Title")
    }

    func testWarningLinesBeforeJSONAndUnavailableVideos() throws {
        let json = try Engine.jsonObject("WARNING: test\n{\"title\":\"ok\",\"id\":\"x\"}\n")
        XCTAssertEqual(json["title"] as? String, "ok")
        XCTAssertNil(Engine.youtubeItem(["id": "x", "title": "[Private video]"]))
    }

    func testProcessCancellationStopsPromptly() async throws {
        let start = Date()
        let task = Task { try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["30"]) }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled process completed successfully") } catch {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testRealConversionsWithBundledTools() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let tools = root.appendingPathComponent("vendor/bin/\(arch)")
        let engine = Engine(tools: tools)
        try engine.checkTools()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("resonance-tests-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let input = temp.appendingPathComponent("sample.mp4")
        try FileManager.default.copyItem(at: root.appendingPathComponent("Tests/Fixtures/sample.mp4"), to: input)
        let item = MediaItem(id: "test", title: "Synthetic test", artist: "Resonance", url: input.absoluteString)
        for format in OutputFormat.audio + OutputFormat.video {
            let output = temp.appendingPathComponent(format.rawValue)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            var options = ExportOptions(destination: output)
            options.format = format
            options.kind = OutputFormat.audio.contains(format) ? .audio : .video
            let source: URL
            if format == .webm {
                source = temp.appendingPathComponent("sample.webm")
                try FileManager.default.copyItem(at: root.appendingPathComponent("Tests/Fixtures/sample.webm"), to: source)
            } else { source = input }
            // Direct file URLs do not expose codec/height metadata to the generic extractor.
            // Supply the known synthetic fixture's metadata, as the YouTube extractor does.
            let info = temp.appendingPathComponent("info-\(format.rawValue).json")
            let fixture: [String: Any] = ["id": "test", "title": "Synthetic test", "extractor": "generic", "extractor_key": "Generic",
                "webpage_url": source.absoluteString, "formats": [["format_id": "fixture", "url": source.absoluteString,
                "ext": format == .webm ? "webm" : "mp4", "height": 90, "width": 160,
                "vcodec": format == .webm ? "vp9" : "avc1.64000a", "acodec": format == .webm ? "opus" : "mp4a.40.2"]]]
            try JSONSerialization.data(withJSONObject: fixture).write(to: info)
            let production = Engine.downloadArguments(item: item, source: source.absoluteString, options: options, directory: output)
            let arguments = ["--enable-file-urls", "--load-info-json", info.path] + Array(production.dropLast(2))
            let text = try await engine.yt(arguments)
            let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
            let result = try XCTUnwrap(files.first(where: { $0.pathExtension == format.extensionName }), "\(format): \(text)")
            let probe = try await ProcessRunner.run(tools.appendingPathComponent("ffprobe"), ["-v", "error", "-show_streams", "-show_format", "-of", "json", result.path])
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(probe.utf8)) as? [String: Any])
            let streams = try XCTUnwrap(json["streams"] as? [[String: Any]])
            XCTAssertTrue(streams.contains { $0["codec_type"] as? String == "audio" }, format.rawValue)
            if options.kind == .video { XCTAssertTrue(streams.contains { $0["codec_type"] as? String == "video" }, format.rawValue) }
            else { XCTAssertFalse(streams.contains { $0["codec_type"] as? String == "video" }, format.rawValue) }
            print("CONVERSION OK: \(format.rawValue)")
        }
    }
}


@main
struct CheckRunner {
    static func main() async {
        let checks = ResonanceTests()
        do {
            try checks.testValidLinksAndSpotifyURI(); print("PASS valid links")
            checks.testRejectsForeignHostsAndNonMediaLinks(); print("PASS rejected links")
            try checks.testSpotifyCollectionParserAndPartialWarning(); print("PASS Spotify collections")
            try checks.testSpotifySingleTrackArtists(); print("PASS Spotify track")
            checks.testDownloadOptionsConstrainVideoAndDoNotFakeLosslessBitrate(); print("PASS export options")
            try checks.testWarningLinesBeforeJSONAndUnavailableVideos(); print("PASS engine responses")
            try await checks.testProcessCancellationStopsPromptly(); print("PASS process cancellation")
            try await checks.testRealConversionsWithBundledTools(); print("PASS all eight real conversions")
            print("ALL 8 CHECK GROUPS PASSED")
        } catch {
            print("FAILED: \(error)")
            exit(1)
        }
    }
}
