import XCTest
@testable import dao

/// M1 脚手架冒烟测试：验证工程配置与常量
final class SmokeTests: XCTestCase {    func testAppConfigConstants() {
        XCTAssertEqual(AppConfig.appName, "dao")
        // 窗口层级必须高于菜单栏（需求：.mainMenu + 3）
        XCTAssertGreaterThan(AppConfig.windowLevel.rawValue, NSWindow.Level.mainMenu.rawValue)
    }

    func testWindowSizes() {
        XCTAssertGreaterThan(AppConfig.expandedWidth, AppConfig.notchWidth)
        // 展开高度紧凑（无底部空余），但仍需容纳顶部行与内容
        XCTAssertGreaterThan(AppConfig.expandedHeight, 150)
    }

    func testCollapsedFrameCenteredOnScreenTop() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = ScreenNotchDetector.windowFrame(for: screen, expansion: .collapsed)
        // 水平居中
        XCTAssertEqual(frame.midX, screen.frame.midX, accuracy: 0.5)
        // 顶边与屏幕顶边对齐，底部与摄像头齐平
        // 高度 = 视觉高度 + 透明拖拽热区（24pt）
        XCTAssertEqual(frame.maxY, screen.frame.maxY, accuracy: 0.5)
        XCTAssertEqual(frame.height, ScreenNotchDetector.collapsedHeight(for: screen))
        // 无媒体会话：与摄像头同宽（纯黑胶囊）
        XCTAssertEqual(frame.width, AppConfig.notchWidth)
    }

    /// 收起态统一宽度：无媒体会话时与摄像头同宽，媒体会话时延伸
    func testCollapsedFrame() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        // 无媒体：与摄像头同宽
        let base = ScreenNotchDetector.collapsedFrame(for: screen)
        XCTAssertEqual(base.width, AppConfig.notchWidth)
        // 媒体会话：延伸宽度
        let extended = ScreenNotchDetector.collapsedFrame(for: screen, extended: true)
        XCTAssertEqual(extended.width, AppConfig.collapsedWidth)
        XCTAssertGreaterThan(extended.width, base.width)
        XCTAssertEqual(extended.midX, screen.frame.midX, accuracy: 0.5)
        XCTAssertEqual(extended.maxY, screen.frame.maxY, accuracy: 0.5)
        XCTAssertEqual(extended.height, ScreenNotchDetector.collapsedHeight(for: screen))
    }

    func testExpandedFrameSymmetric() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = ScreenNotchDetector.windowFrame(for: screen, expansion: .expanded)
        // 顶边与屏幕顶边对齐
        XCTAssertEqual(frame.maxY, screen.frame.maxY, accuracy: 0.5)
        // 左右对称：以屏幕中心居中（刘海即屏幕中心）
        XCTAssertEqual(frame.midX, screen.frame.midX, accuracy: 0.5)
        XCTAssertEqual(frame.size, CGSize(width: AppConfig.expandedWidth, height: AppConfig.expandedHeight))
        // 横向长方形（倒着的长方形）
        XCTAssertGreaterThan(AppConfig.expandedWidth, AppConfig.expandedHeight)
    }

    /// 固定窗 = expanded 几何（Strategy A：窗不随收展 resize）
    func testFixedWindowEqualsExpanded() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let fixed = ScreenNotchDetector.windowFrame(for: screen, expansion: .expanded)
        XCTAssertEqual(fixed.maxY, screen.frame.maxY, accuracy: 0.5)
        XCTAssertEqual(fixed.size.width, AppConfig.expandedWidth, accuracy: 0.5)
        XCTAssertEqual(fixed.size.height, AppConfig.expandedHeight, accuracy: 0.5)
    }

    /// 视觉 frame：收起随媒体宽，展开=固定窗；均贴顶
    func testVisualFrameCollapsedUsesMediaWidth() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let collapsed = ScreenNotchDetector.visualFrame(
            for: screen, expansion: .collapsed, mediaActive: false
        )
        XCTAssertEqual(collapsed.width, AppConfig.notchWidth, accuracy: 0.5)
        XCTAssertEqual(collapsed.maxY, screen.frame.maxY, accuracy: 0.5)

        let media = ScreenNotchDetector.visualFrame(
            for: screen, expansion: .collapsed, mediaActive: true
        )
        XCTAssertEqual(media.width, AppConfig.collapsedWidth, accuracy: 0.5)
        XCTAssertEqual(media.maxY, screen.frame.maxY, accuracy: 0.5)

        let expanded = ScreenNotchDetector.visualFrame(
            for: screen, expansion: .expanded, mediaActive: false
        )
        XCTAssertEqual(
            expanded.size,
            CGSize(width: AppConfig.expandedWidth, height: AppConfig.expandedHeight)
        )
    }

    /// 固定窗本地坐标：收起胶囊贴窗顶（AppKit y 高侧）
    func testVisualRectInFixedWindowPinnedTop() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let window = ScreenNotchDetector.windowFrame(for: screen, expansion: .expanded)
        let local = ScreenNotchDetector.visualRectInFixedWindow(
            for: screen, expansion: .collapsed, mediaActive: false
        )
        XCTAssertEqual(local.width, AppConfig.notchWidth, accuracy: 0.5)
        XCTAssertEqual(local.maxY, window.height, accuracy: 0.5)
        XCTAssertEqual(local.midX, window.width / 2, accuracy: 0.5)
    }
}
