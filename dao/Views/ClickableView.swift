import AppKit
import SwiftUI

/// 点击 + 悬停视图（AppKit 层处理）
///
/// - 点击：mouseDown 直接触发（非激活面板点击稳定）
/// - 悬停：HoverManager（窗口级 mouseMoved + 按钮区域判定；
///   非激活 NSPanel 中 SwiftUI/AppKit tracking 均不可靠）
struct ClickableView: NSViewRepresentable {
    /// 点击回调
    var action: () -> Void
    /// 悬停回调（true = 进入，false = 离开）
    var onHover: ((Bool) -> Void)?
    /// 拖出回调（鼠标按下后拖动超过阈值时调用，返回拖拽项；nil = 不拖出）
    var onDragBegan: (() -> NSDraggingItem?)?
    /// 拖拽会话结束（operation 非空 = 拖出成功）
    var onDragEnded: ((NSDragOperation) -> Void)?

    /// 支持 perform: 标签构造（与 onTapGesture(perform:) 风格一致）
    init(perform action: @escaping () -> Void) {
        self.action = action
    }

    /// 完整构造（点击 + 悬停 + 拖出）
    init(
        perform action: @escaping () -> Void,
        onHover: ((Bool) -> Void)? = nil,
        onDragBegan: (() -> NSDraggingItem?)? = nil,
        onDragEnded: ((NSDragOperation) -> Void)? = nil
    ) {
        self.action = action
        self.onHover = onHover
        self.onDragBegan = onDragBegan
        self.onDragEnded = onDragEnded
    }

    func makeNSView(context: Context) -> ClickNSView {
        let view = ClickNSView()
        view.action = action
        view.onHoverChange = onHover
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: ClickNSView, context: Context) {
        nsView.action = action
        nsView.onHoverChange = onHover
        nsView.onDragBegan = onDragBegan
        nsView.onDragEnded = onDragEnded
    }

    /// 点击 + 悬停捕获视图
    final class ClickNSView: NSView {
        var action: () -> Void = {}
        var onHoverChange: ((Bool) -> Void)?
        var onDragBegan: (() -> NSDraggingItem?)?
        var onDragEnded: ((NSDragOperation) -> Void)?

        /// 当前悬停状态（HoverManager 维护）
        var isHovering = false
        /// 按下事件（拖出判定用）
        private var mouseDownEvent: NSEvent?
        /// 拖出判定阈值（pt）
        private let dragThreshold: CGFloat = 5

        override var mouseDownCanMoveWindow: Bool { false }

        /// 非激活窗口首次点击也传递给视图（否则第一次点击被激活消耗，偶发需点两次）
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // viewDidMoveToWindow 在主线程调用（assumeIsolated 安全）
            MainActor.assumeIsolated {
                if window != nil {
                    HoverManager.shared.register(self)
                } else {
                    HoverManager.shared.unregister(self)
                }
            }
        }
        // 注意：不在 deinit 中访问 HoverManager（Swift 6 隔离下捕获销毁中的
        // self 会崩溃）；HoverManager 使用弱引用，失效按钮自动清理

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            action()
        }

        /// 拖动超过阈值 → 发起拖拽会话（文件/链接/文本拖出）
        override func mouseDragged(with event: NSEvent) {
            guard let down = mouseDownEvent, onDragBegan != nil else {
                super.mouseDragged(with: event)
                return
            }
            let distance = hypot(
                event.locationInWindow.x - down.locationInWindow.x,
                event.locationInWindow.y - down.locationInWindow.y
            )
            guard distance > dragThreshold, let item = onDragBegan?() else {
                super.mouseDragged(with: event)
                return
            }
            mouseDownEvent = nil
            beginDraggingSession(with: [item], event: event, source: self)
        }
    }
}

// MARK: - NSDraggingSource（拖出）

extension ClickableView.ClickNSView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // 仅 .copy：拖出目标执行复制（源文件不动），移除条目时再删除副本——
        // 若允许 .move，Finder 移动源文件与移除条目的文件删除竞争，内容会丢失
        [.copy]
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onDragEnded?(operation)
    }
}
