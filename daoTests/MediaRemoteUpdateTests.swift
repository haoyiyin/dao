import XCTest
@testable import dao

/// MediaRemote 流 JSON 解码与状态映射单元测试
final class MediaRemoteUpdateTests: XCTestCase {
    /// 完整 JSON 解码 + 状态映射
    func testDecodeFullUpdate() throws {
        let json = """
        {
            "title": "Blinding Lights",
            "artist": "The Weeknd",
            "album": "After Hours",
            "duration": 200.3,
            "elapsedTime": 42.5,
            "timestamp": "2026-08-01T09:44:22Z",
            "playing": true,
            "playbackRate": 1.0,
            "bundleIdentifier": "com.spotify.client",
            "artworkMimeType": "image/jpeg",
            "artworkData": "aGVsbG8=",
            "shuffleMode": 1,
            "repeatMode": 2,
            "isMusicApp": true
        }
        """
        let update = try decode(json)

        XCTAssertEqual(update.title, "Blinding Lights")
        XCTAssertEqual(update.artist, "The Weeknd")
        XCTAssertEqual(update.album, "After Hours")
        XCTAssertEqual(update.duration, 200.3)
        XCTAssertEqual(update.elapsedTime, 42.5)
        XCTAssertEqual(update.playbackRate, 1.0)
        XCTAssertEqual(update.shuffleMode, 1)
        XCTAssertEqual(update.repeatMode, 2)

        let state = MediaState(update: update)
        XCTAssertEqual(state.title, "Blinding Lights")
        XCTAssertEqual(state.artworkData, Data("hello".utf8))
        XCTAssertEqual(state.bundleIdentifier, "com.spotify.client")
        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.isActive)
        // ISO8601 时间戳 → epoch 秒
        let expected = ISO8601DateFormatter().date(from: "2026-08-01T09:44:22Z")?.timeIntervalSince1970
        XCTAssertEqual(state.timestamp, expected)
    }

    /// 小数秒时间戳兼容
    func testTimestampWithFractionalSeconds() throws {
        let json = """
        {"title": "T", "timestamp": "2026-08-01T09:44:22.500Z"}
        """
        let state = MediaState(update: try decode(json))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = formatter.date(from: "2026-08-01T09:44:22.500Z")?.timeIntervalSince1970
        XCTAssertEqual(state.timestamp, expected)
    }

    /// 字段缺失容忍：部分应用不上报 artist/artwork
    func testDecodeMinimalUpdate() throws {
        let json = """
        {"title": "Podcast Ep 1", "playing": false, "playbackRate": 0}
        """
        let state = MediaState(update: try decode(json))

        XCTAssertEqual(state.title, "Podcast Ep 1")
        XCTAssertNil(state.artist)
        XCTAssertNil(state.artworkData)
        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.isActive)
    }

    /// 暂停时应用可能不上报 playbackRate → 用 playing 字段兜底判断
    func testPausedWithoutPlaybackRate() throws {
        let json = """
        {"title": "T", "playing": false}
        """
        let state = MediaState(update: try decode(json))
        XCTAssertFalse(state.isPlaying)
    }

    /// playing 字段缺失 → 回退 playbackRate 判断
    func testPlayingFlagFallback() throws {
        let json = """
        {"title": "T", "playbackRate": 0}
        """
        let state = MediaState(update: try decode(json))
        XCTAssertFalse(state.isPlaying)
    }

    /// bundleIdentifier 缺失时回退 parentApplicationBundleIdentifier
    func testBundleFallback() throws {
        let json = """
        {"title": "T", "parentApplicationBundleIdentifier": "org.mozilla.firefox"}
        """
        let state = MediaState(update: try decode(json))
        XCTAssertEqual(state.bundleIdentifier, "org.mozilla.firefox")
    }

    /// 流输出 null（无活跃会话）→ 空状态
    func testNullUpdateYieldsEmptyState() {
        let state = MediaState(update: nil)
        XCTAssertEqual(state, .empty)
        XCTAssertFalse(state.isActive)
    }

    /// 浏览器 bundle 识别（含 helper 前缀）
    func testBrowserAppDetection() {
        XCTAssertTrue(MediaState.isBrowserApp("com.apple.Safari"))
        XCTAssertTrue(MediaState.isBrowserApp("com.google.Chrome"))
        XCTAssertTrue(MediaState.isBrowserApp("com.google.Chrome.helper"))
        XCTAssertTrue(MediaState.isBrowserApp("org.mozilla.firefox"))
        XCTAssertTrue(MediaState.isBrowserApp("company.thebrowser.Browser"))
        XCTAssertFalse(MediaState.isBrowserApp("com.spotify.client"))
        XCTAssertFalse(MediaState.isBrowserApp("com.apple.Music"))
        XCTAssertFalse(MediaState.isBrowserApp(nil))
        XCTAssertFalse(MediaState.isBrowserApp(""))
    }

    /// 浏览器垫底决策：非浏览器流始终采纳并清锁定；锁定时忽略浏览器流
    func testBrowserDemotionDecision() {
        var browser = MediaState()
        browser.bundleIdentifier = "com.apple.Safari"
        browser.isActive = true
        var music = MediaState()
        music.bundleIdentifier = "com.spotify.client"
        music.isActive = true

        let open = MediaState.browserDemotionDecision(newState: browser, browserDemoted: false)
        XCTAssertTrue(open.apply)
        XCTAssertFalse(open.clearDemotion)

        let locked = MediaState.browserDemotionDecision(newState: browser, browserDemoted: true)
        XCTAssertFalse(locked.apply)
        XCTAssertFalse(locked.clearDemotion)

        let native = MediaState.browserDemotionDecision(newState: music, browserDemoted: true)
        XCTAssertTrue(native.apply)
        XCTAssertTrue(native.clearDemotion)
    }

    /// 损坏 JSON → 解码失败（流层会跳过该行）
    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try decode("not json"))
    }

    // MARK: - 辅助

    private func decode(_ json: String) throws -> MediaRemoteUpdate {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(MediaRemoteUpdate.self, from: data)
    }
}
