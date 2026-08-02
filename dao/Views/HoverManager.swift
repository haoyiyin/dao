import AppKit
import Foundation

/// 悬停管理器：窗口级 mouseMoved 分发 + 按钮区域判定
///
/// 非激活 NSPanel 中 SwiftUI onHover/onContinuousHover 与 AppKit tracking area
/// 均不可靠（实测不触发）。方案：窗口接收 mouseMoved（acceptsMouseMovedEvents）
/// → local monitor 记录鼠标窗口坐标 → 遍历注册的按钮视图判定悬停状态。
@MainActor
final class HoverManager {
    /// 全局单例
    static let shared = HoverManager()

    /// 注册的按钮弱引用
    private var buttons: [ObjectIdentifier: WeakBox] = [:]

    /// 鼠标窗口坐标（左下原点；nil = 不在本应用窗口）
    private var mouseLocation: CGPoint?

    private init() {}

    /// 注册按钮（挂窗时）
    func register(_ view: ClickableView.ClickNSView) {
        buttons[ObjectIdentifier(view)] = WeakBox(view: view)
    }

    /// 注销按钮（卸载时）
    func unregister(_ view: ClickableView.ClickNSView) {
        buttons.removeValue(forKey: ObjectIdentifier(view))
    }

    /// 更新鼠标位置（屏幕坐标，左下原点）并分发悬停状态
    func updateMouseLocation(_ location: CGPoint) {
        mouseLocation = location
        // 清理失效引用
        buttons = buttons.filter { $0.value.view != nil }

        for box in buttons.values {
            guard let view = box.view, let window = view.window else { continue }
            // 视图屏幕坐标（左下原点，与 NSEvent.mouseLocation 一致）
            let rectInScreen = window.convertToScreen(view.convert(view.bounds, to: nil))
            let inside = rectInScreen.contains(location)
            if inside != view.isHovering {
                view.isHovering = inside
                view.onHoverChange?(inside)
            }
        }
    }

    /// 鼠标离开窗口（.mouseExited 时重置）
    func mouseLeftWindow() {
        mouseLocation = nil
        for box in buttons.values {
            guard let view = box.view, view.isHovering else { continue }
            view.isHovering = false
            view.onHoverChange?(false)
        }
    }

    /// 弱引用包装
    private final class WeakBox {
        weak var view: ClickableView.ClickNSView?
        init(view: ClickableView.ClickNSView) {
            self.view = view
        }
    }
}
