import XCTest
@testable import dao

/// 媒体逻辑单元测试：路由降级、进度外推、AppleScript 脚本构造
final class MediaLogicTests: XCTestCase {
    // MARK: - 测试桩

    /// 可编程 Mock 控制器
    private final class MockController: MediaControlling {
        var isAvailable = true
        var results: [Bool] = []
        var toggleCount = 0
        var seekCount = 0

        func play() async -> Bool { results.isEmpty ? true : results.removeFirst() }
        func pause() async -> Bool { results.isEmpty ? true : results.removeFirst() }
        func togglePlayPause() async -> Bool { toggleCount += 1; return results.isEmpty ? true : results.removeFirst() }
        func nextTrack() async -> Bool { results.isEmpty ? true : results.removeFirst() }
        func previousTrack() async -> Bool { results.isEmpty ? true : results.removeFirst() }
        func seek(to time: TimeInterval) async -> Bool { seekCount += 1; return results.isEmpty ? true : results.removeFirst() }
    }

    // MARK: - 路由测试

    /// 主链路成功 → 兜底不调用
    func testRouterUsesPrimaryOnSuccess() async {
        let primary = MockController()
        let fallback = MockController()
        let router = MediaCommandRouter(primary: primary, fallback: fallback)

        let result = await router.togglePlayPause()

        XCTAssertTrue(result)
        XCTAssertEqual(primary.toggleCount, 1)
        XCTAssertEqual(fallback.toggleCount, 0)
    }

    /// 主链路失败 → 自动降级兜底
    func testRouterFallsBackOnFailure() async {
        let primary = MockController()
        primary.results = [false]
        let fallback = MockController()
        let router = MediaCommandRouter(primary: primary, fallback: fallback)

        let result = await router.togglePlayPause()

        XCTAssertTrue(result)
        XCTAssertEqual(primary.toggleCount, 1)
        XCTAssertEqual(fallback.toggleCount, 1)
    }

    /// 主链路不可用 → 直接走兜底
    func testRouterSkipsUnavailablePrimary() async {
        let primary = MockController()
        primary.isAvailable = false
        let fallback = MockController()
        let router = MediaCommandRouter(primary: primary, fallback: fallback)

        let result = await router.seek(to: 30)

        XCTAssertTrue(result)
        XCTAssertEqual(primary.seekCount, 0)
        XCTAssertEqual(fallback.seekCount, 1)
    }

    // MARK: - 进度外推测试

    private func makeState(elapsed: TimeInterval, timestamp: TimeInterval, rate: Double, duration: TimeInterval? = nil) -> MediaState {
        var state = MediaState()
        state.elapsedTime = elapsed
        state.timestamp = timestamp
        state.playbackRate = rate
        state.duration = duration
        state.isActive = true
        return state
    }

    /// 播放中：elapsed + delta × rate
    func testExtrapolatePlaying() {
        let state = makeState(elapsed: 100, timestamp: 1000, rate: 1.0)
        XCTAssertEqual(MediaManager.extrapolateElapsed(state: state, now: 1015), 115)
    }

    /// 倍速播放
    func testExtrapolateWithRate() {
        let state = makeState(elapsed: 100, timestamp: 1000, rate: 2.0)
        XCTAssertEqual(MediaManager.extrapolateElapsed(state: state, now: 1015), 130)
    }

    /// 暂停（rate=0）→ 不外推
    func testExtrapolatePaused() {
        let state = makeState(elapsed: 100, timestamp: 1000, rate: 0)
        XCTAssertNil(MediaManager.extrapolateElapsed(state: state, now: 1015))
    }

    /// 外推封顶 duration
    func testExtrapolateCapsAtDuration() {
        let state = makeState(elapsed: 200, timestamp: 1000, rate: 1.0, duration: 210)
        XCTAssertEqual(MediaManager.extrapolateElapsed(state: state, now: 1015), 210)
    }

    /// 无时间戳 → 不外推
    func testExtrapolateWithoutTimestamp() {
        var state = makeState(elapsed: 100, timestamp: 1000, rate: 1.0)
        state.timestamp = nil
        XCTAssertNil(MediaManager.extrapolateElapsed(state: state, now: 1015))
    }

    // MARK: - AppleScript 脚本构造测试

    func testScriptAppMapping() throws {
        // appName 现在返回可选：已知应用映射成功，未知应用返回 nil
        XCTAssertEqual(AppleScriptController.appName(for: "com.apple.Music"), "Music")
        XCTAssertEqual(AppleScriptController.appName(for: "com.spotify.client"), "Spotify")
        XCTAssertEqual(AppleScriptController.appName(for: "com.netease.163music"), "NeteaseMusic")
        XCTAssertNil(AppleScriptController.appName(for: "unknown.app"))
    }

    func testScriptGeneration() {
        XCTAssertEqual(
            AppleScriptController.script(for: "Spotify", command: .togglePlayPause),
            "tell application \"Spotify\" to playpause"
        )
        XCTAssertEqual(
            AppleScriptController.script(for: "Music", command: .nextTrack),
            "tell application \"Music\" to next track"
        )
        XCTAssertEqual(
            AppleScriptController.script(for: "Spotify", command: .seek(42.5)),
            "tell application \"Spotify\" to set player position to 42.5"
        )
        XCTAssertEqual(
            AppleScriptController.script(for: "Music", command: .setVolume(0.5)),
            "tell application \"Music\" to set sound volume to 50"
        )
    }

    /// 音量越界钳制
    func testScriptVolumeClamping() {
        XCTAssertEqual(
            AppleScriptController.script(for: "Music", command: .setVolume(1.5)),
            "tell application \"Music\" to set sound volume to 100"
        )
        XCTAssertEqual(
            AppleScriptController.script(for: "Music", command: .setVolume(-0.5)),
            "tell application \"Music\" to set sound volume to 0"
        )
    }
}
