import AppKit
import Combine
import QuartzCore
import SwiftUI

/// 灵动岛展开状态
@MainActor
final class NotchExpansionState: ObservableObject {
    /// 当前展开状态
    @Published var expansion: NotchExpansion = .collapsed
}

/// 展开状态枚举
enum NotchExpansion: Equatable {
    /// 收起：仅显示刘海胶囊
    case collapsed
    /// 展开：显示完整功能面板
    case expanded
}

/// 灵动岛专用 NSPanel
///
/// 关键配置：
/// - `.nonactivatingPanel`：不抢占其他应用的焦点
/// - 永不成为 key（boring.notch 同款）：key 窗口会被 Space 系统绑定到当前
///   桌面，切换后不跟随刘海；交互走手势不依赖 key
/// - `level = .mainMenu + 3`：悬浮于菜单栏之上
/// - `.canJoinAllSpaces` / `.stationary`：多桌面下固定在刘海位置
final class NotchPanel: NSPanel {
    /// 允许内容尺寸变化（仅当窗口尺寸由我们控制时）
    private var allowsContentSizeChange = false
    /// 设置窗口 frame（由我们控制，允许内部 contentSize 联动）
    func applyFrame(_ frame: NSRect) {
        allowsContentSizeChange = true
        setFrame(frame, display: true)
        allowsContentSizeChange = false
    }

    /// 智能拦截：位置移动放行（didMove 纠正需要），尺寸变化需我们的许可
    /// （hosting 内容布局会尝试撑大窗口，实测 setContentSize 拦截不覆盖该路径）
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        if allowsContentSizeChange || frameRect.size == frame.size {
            super.setFrame(frameRect, display: flag)
        } else {
            // 仅保留位置变化，尺寸保持当前值
            super.setFrame(NSRect(origin: frameRect.origin, size: frame.size), display: flag)
        }
    }

    /// 拦截 hosting 的 preferredContentSize 驱动
    ///
    /// macOS 26 上 NSHostingView 会调用 window.setContentSize 把窗口撑到
    /// 内容固有尺寸（即使包装/禁用 sizingOptions 也无效），此处统一拦截。
    override func setContentSize(_ size: NSSize) {
        guard allowsContentSizeChange else { return }
        super.setContentSize(size)
    }
    /// 允许面板成为 key window（非激活面板默认为 false）
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            // 固定窗架构：初始即 expanded 几何，避免启动瞬间再 resize
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: AppConfig.expandedWidth,
                height: AppConfig.expandedHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // 浮动面板行为（boring.notch 同款）
        isFloatingPanel = true
        // 接收 mouseMoved 事件：HoverManager 悬停判定依赖它
        acceptsMouseMovedEvents = true
        level = AppConfig.windowLevel
        // 跟随刘海（boring.notch 同款）：canJoinAllSpaces 所有桌面显示 +
        // fullScreenAuxiliary 全屏可见 + ignoresCycle。
        // 不使用 .stationary：用户实测 boring.notch 在切换动画中窗口跟随滑动，
        // stationary 会固定窗口位置导致动画中不与菜单栏/刘海同步
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
}
