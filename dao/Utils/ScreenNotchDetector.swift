import AppKit
import Defaults
import SwiftUI

/// 屏幕刘海检测与窗口几何计算
enum ScreenNotchDetector {
    /// 刘海屏判定阈值：刘海屏菜单栏高度 ≥ 34pt（普通屏约 24-25pt）
    private static let notchThreshold: CGFloat = 30

    /// 屏幕是否带物理刘海
    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top >= notchThreshold
    }

    /// 灵动岛宽度：刘海屏用物理宽度，非刘海屏用虚拟宽度（可配置）
    static func notchWidth(for screen: NSScreen) -> CGFloat {
        if hasNotch(screen) { return AppConfig.notchWidth }
        return Defaults[.showVirtualNotch] ? AppConfig.virtualNotchWidth : AppConfig.minimalNotchWidth
    }

    /// 收起态高度：刘海屏取菜单栏高度（与刘海齐平），非刘海屏用虚拟高度
    static func collapsedHeight(for screen: NSScreen) -> CGFloat {
        if hasNotch(screen) { return screen.safeAreaInsets.top }
        return Defaults[.showVirtualNotch] ? AppConfig.virtualNotchHeight : 24
    }

    /// 计算窗口 frame（屏幕坐标系，原点在左下角）
    ///
    /// - 收起：顶部居中，小矩形（宽度略大于摄像头，底部与摄像头齐平）
    /// - 展开：横向长方形，以刘海为中心左右对称
    static func windowFrame(for screen: NSScreen, expansion: NotchExpansion) -> CGRect {
        switch expansion {
        case .collapsed:
            return collapsedFrame(for: screen)
        case .expanded:
            let width = AppConfig.expandedWidth
            // 左右对称：以刘海中心为中心居中
            // 顶部精确对齐屏幕顶（boring.notch 思路）：顶部圆角从屏幕边缘
            // 开始自然衔接——窗口超出屏幕会导致圆角被边缘横切（衔接不流畅）
            return CGRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.maxY - AppConfig.expandedHeight,
                width: width,
                height: AppConfig.expandedHeight
            )
        }
    }

    /// 收起态 frame：无媒体会话时与摄像头同宽（纯黑胶囊），
    /// 有媒体会话时向两侧延伸（放置媒体信息与频率线）
    /// 高度 = 视觉高度（刘海/菜单栏）；拖拽热区由全局监听区域扩展（不改变窗口）
    static func collapsedFrame(for screen: NSScreen, extended: Bool = false) -> CGRect {
        let width = extended ? AppConfig.collapsedWidth : AppConfig.notchWidth
        let height = collapsedHeight(for: screen)
        return CGRect(
            x: screen.frame.midX - width / 2,
            // 顶部精确对齐屏幕顶（圆角自然衔接）；底部与刘海底部齐平
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// 视觉内容 frame（屏幕坐标）：固定窗架构下 hitTest / 拖拽热区 / SwiftUI shape 同源
    /// - expanded：400×166 全窗
    /// - collapsed：185 或 265 × 刘海高，顶中贴屏幕顶
    static func visualFrame(
        for screen: NSScreen,
        expansion: NotchExpansion,
        mediaActive: Bool
    ) -> CGRect {
        switch expansion {
        case .expanded:
            return windowFrame(for: screen, expansion: .expanded)
        case .collapsed:
            return collapsedFrame(for: screen, extended: mediaActive)
        }
    }

    /// 视觉内容在固定展开窗内的本地 rect（AppKit 坐标：原点左下）
    /// 用于 contentView hitTest / 热区（窗恒 expanded，胶囊贴顶居中）
    static func visualRectInFixedWindow(
        for screen: NSScreen,
        expansion: NotchExpansion,
        mediaActive: Bool
    ) -> CGRect {
        let window = windowFrame(for: screen, expansion: .expanded)
        let visual = visualFrame(for: screen, expansion: expansion, mediaActive: mediaActive)
        return CGRect(
            x: visual.minX - window.minX,
            y: visual.minY - window.minY,
            width: visual.width,
            height: visual.height
        )
    }

    /// 展开面板在屏幕上的右边缘（用于按钮推开图标计算）
    static func expandedRightEdge(for screen: NSScreen) -> CGFloat {
        screen.frame.midX + AppConfig.expandedWidth / 2
    }

    /// 面板所在屏幕（近似：鼠标所在屏，其次主屏）
    static func currentScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
