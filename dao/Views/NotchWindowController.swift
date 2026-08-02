import AppKit
import Combine
import Defaults
import QuartzCore
import SwiftUI

/// 灵动岛窗口控制器
///
/// 职责：
/// - 创建与管理 NSPanel，挂载 SwiftUI 内容（NotchView）
/// - 计算窗口位置（刘海/虚拟刘海、多屏、菜单栏高度变化）
/// - 驱动窗口尺寸动画（展开/收起）
@MainActor
final class NotchWindowController: NSObject {
    /// 展开状态（SwiftUI 与控制器共享）
    let state = NotchExpansionState()

    private let panel: NotchPanel
    private var cancellables = Set<AnyCancellable>()

    /// 目标屏幕：优先鼠标所在屏（仅在线屏），其次主屏
    private var targetScreen: NSScreen {
        let mouse = NSEvent.mouseLocation
        // 已断开的镜像/外接屏空间仍存在于 NSScreen.screens（frame 含鼠标），
        // 必须过滤：只跟随在线屏幕，否则窗口会跑到用户看不到的屏上
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) && Self.isOnline($0) }) {
            return screen
        }
        if let main = NSScreen.main, Self.isOnline(main) {
            return main
        }
        return NSScreen.screens.first(where: Self.isOnline) ?? NSScreen.screens[0]
    }

    /// 屏幕是否在线（CGDisplayIsOnline）
    private static func isOnline(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return true
        }
        return CGDisplayIsOnline(CGDirectDisplayID(number.uint32Value)) != 0
    }

    override init() {
        panel = NotchPanel()
        super.init()

        // 挂载 SwiftUI 内容（注入全局 Manager）
        setupContentView()

        // 初始定位
        reposition()

        // 加入专属空间（跟随刘海；CGS 创建失败自动降级）
        joinNotchSpace()

        setupObservers()
    }

    /// 订阅窗口/状态变化（屏幕、展开状态、媒体会话、外部 resize）
    /// 悬停监视：窗口级 mouseMoved → HoverManager（按钮悬停高亮）
    private func setupObservers() {
        setupHoverMonitor()

        // 显示器参数变化（分辨率/布局/菜单栏高度）→ 重定位
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.reposition() }
            }
            .store(in: &cancellables)

        // 面板跨屏 → 重定位
        NotificationCenter.default
            .publisher(for: NSWindow.didChangeScreenNotification, object: panel)
            .sink { [weak self] _ in
                Task { @MainActor in self?.reposition() }
            }
            .store(in: &cancellables)

        // 展开状态变化 → 固定窗架构下仅同步 hitTest 视觉区（内容动画在 SwiftUI 内）
        state.$expansion
            .removeDuplicates()
            .sink { [weak self] expansion in
                Task { @MainActor in
                    self?.animateWindowSize(to: expansion)
                }
            }
            .store(in: &cancellables)

        // 媒体会话状态变化 → 收起态视觉宽 185↔265（窗不改，只刷新 hitTest 区）
        MediaManager.shared.$state
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.state.expansion == .collapsed else { return }
                    self.syncHitTestVisualFrame()
                }
            }
            .store(in: &cancellables)

        // 窗口被外部（hosting 内容布局）resize → 纠正
        // 注意：仅 didResize（didMove 纠正会在 Space 切换动画中触发 setFrame，
        // 导致窗口内容重建闪烁/动画中不跟随）
        NotificationCenter.default
            .publisher(for: NSWindow.didResizeNotification, object: panel)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.correctFrameDrift()
                }
            }
            .store(in: &cancellables)
    }

    /// 窗口当前是否可见
    var isVisible: Bool { panel.isVisible }

    /// 窗口加入灵动岛专属空间（CGS 私有 API）：随桌面切换动画滑动跟随
    /// （绑定刘海位置）；只加入不移除正常空间——拖拽命中不受影响
    private func joinNotchSpace() {
        NotchSpaceManager.shared.addWindow(panel)
    }

    /// 挂载 SwiftUI 内容（注入全局 Manager）
    ///
    /// contentViewController 方案：内容布局正确跟随窗口（wrapper/NSHostingView
    /// 方案在 macOS 26 上内容按理想尺寸布局导致偏移）；窗口被内容撑大的问题
    /// 由 NotchPanel 的 setFrame/setContentSize 智能拦截解决。
    private func setupContentView() {
        // boring.notch 同款：window.contentView = NSHostingView 直接挂载。
        // （contentViewController 挂载在 Space 切换动画中内容不渲染——媒体信息丢失）
        // 内容尺寸由 NotchView 显式绑定 windowSizeProvider（窗口尺寸），
        // 避免 hosting 按内容理想尺寸布局导致偏移。
        let hostingView = NSHostingView<AnyView>(
            rootView: AnyView(
                NotchView(state: state)
                    .environmentObject(windowSizeProvider)
                    .environmentObject(LanguageManager.shared)
                    .environmentObject(MediaManager.shared)
                    .environmentObject(ShelfManager.shared)
                    .environmentObject(SystemMonitor.shared)
            )
        )
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = panel.contentView?.bounds ?? .zero

        // 拖拽容器（contentView 根）：pasteboard 全类型接收
        // （NSFilenamesPboardType 拿到 MD 等文本文件的真实文件名；
        // SwiftUI onDrop 对文本类文件只给内容类型无法取文件名）
        // 注意：容器与 hosting 初始 frame 必须用窗口尺寸（此时 contentView
        // 仍为 nil，取 .zero 会导致内容不覆盖全窗口、左侧露出壁纸）
        let container = DragDropContainerView(
            frame: NSRect(origin: .zero, size: panel.frame.size)
        )
        container.autoresizingMask = [.width, .height]
        container.onDragEnter = { [weak self] in
            self?.handleDragEnter()
        }
        container.onDrop = { [weak self] items in
            self?.handleDragDrop(items)
        }
        container.addSubview(hostingView)
        hostingView.frame = container.bounds
        panel.contentView = container

        // 全局拖拽监听：拖拽光标进入视觉胶囊即展开
        setupGlobalDragMonitor()
    }

    /// 全局 mouseDragged 监听（拖拽光标进入视觉胶囊 → 展开）
    ///
    /// 命中区仅视觉胶囊（±2pt 容差），无底部透明扩展。
    /// 光标在视觉胶囊内且窗口收起时立即展开。
    private func setupGlobalDragMonitor() {
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.expansion == .collapsed, self.panel.isVisible else { return }
                let location = NSEvent.mouseLocation
                // 拖拽热区：收起态黑胶囊 only（禁止用固定窗 400×166）
                let hotzone = self.collapsedHoverZoneOnScreen().insetBy(dx: -2, dy: -2)
                if hotzone.contains(location) {
                    self.handleDragEnter()
                }
            }
        }
    }

    /// 拖拽进入：立即展开并切换到传输抽屉
    private func handleDragEnter() {
        NotificationCenter.default.post(name: .notchDragEntered, object: nil)
        state.expansion = .expanded
    }

    /// 拖放完成：文件/文本落 Shelf + 通知视图显示结果提示
    private func handleDragDrop(_ items: DroppedItems) {
        var count = 0
        let files = ShelfManager.shared.addFiles(items.fileURLs)
        for fileData in items.fileDatas where ShelfManager.shared.addFileData(fileData.data, name: fileData.name) != nil {
            count += 1
        }
        for text in items.texts where !text.isEmpty {
            if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                ShelfManager.shared.addLink(url)
            } else {
                ShelfManager.shared.addText(text)
            }
            count += 1
        }
        NotificationCenter.default.post(
            name: .notchDragDropped,
            object: nil,
            userInfo: ["count": files.count + count]
        )
    }

    /// 窗口尺寸提供器（NotchView 显式绑定，解决 macOS 26 hosting 偏移）
    let windowSizeProvider = WindowSizeProvider()

    /// 显示窗口（orderFrontRegardless：不激活应用；不 makeKey——boring.notch 同款）
    func show() {
        panel.orderFrontRegardless()
    }

    /// 隐藏窗口
    func hide() {
        panel.orderOut(nil)
    }

    // MARK: - 私有

    /// 悬停监视：local + global mouseMoved
    /// - HoverManager：按钮高亮
    /// - 岛展开/收起：仅屏幕坐标视觉胶囊（固定窗透明区不展开）
    private var hoverMonitor: Any?
    private var hoverMonitorExit: Any?
    private var islandHoverGlobalMonitor: Any?
    /// 岛悬停展开/收起延迟任务
    private var islandHoverTask: Task<Void, Never>?

    private func setupHoverMonitor() {
        guard hoverMonitor == nil else { return }
        // AppKit monitor 回调已在主线程；禁止再包 Task，避免移入/移出乱序
        hoverMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            let location = NSEvent.mouseLocation
            HoverManager.shared.updateMouseLocation(location)
            self?.handleIslandHoverMove(at: location)
            return event
        }
        hoverMonitorExit = NSEvent.addLocalMonitorForEvents(matching: .mouseExited) { [weak self] event in
            HoverManager.shared.mouseLeftWindow()
            self?.handleIslandHoverMove(at: NSEvent.mouseLocation)
            return event
        }
        // global：hitTest 穿透区/窗外移动（local 收不到；global 收不到本 app 内事件）
        if islandHoverGlobalMonitor == nil {
            islandHoverGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                // global 回调线程不保证主线程
                DispatchQueue.main.async {
                    self?.handleIslandHoverMove(at: NSEvent.mouseLocation)
                }
            }
        }
    }

    /// 收起态悬停/拖拽触发区：真实 panel 顶中黑胶囊（非固定窗 400×166）
    private func collapsedHoverZoneOnScreen() -> CGRect {
        let pf = panel.frame
        let height = ScreenNotchDetector.collapsedHeight(for: targetScreen)
        let width = MediaManager.shared.state.isActive
            ? AppConfig.collapsedWidth : AppConfig.notchWidth
        return CGRect(
            x: pf.midX - width / 2,
            y: pf.maxY - height,
            width: width,
            height: height
        )
    }

    /// 展开态保持区：真实 panel 全窗
    private func expandedHoverZoneOnScreen() -> CGRect {
        panel.frame
    }

    /// 岛悬停：收起只认黑胶囊；胶囊外立刻取消待展开
    private func handleIslandHoverMove(at location: CGPoint) {
        switch state.expansion {
        case .collapsed:
            if collapsedHoverZoneOnScreen().contains(location) {
                scheduleIslandExpand()
            } else {
                islandHoverTask?.cancel()
                islandHoverTask = nil
            }
        case .expanded:
            if expandedHoverZoneOnScreen().contains(location) {
                islandHoverTask?.cancel()
                islandHoverTask = nil
            } else {
                scheduleIslandCollapse()
            }
        }
    }

    private func scheduleIslandExpand() {
        if islandHoverTask != nil { return }
        islandHoverTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Defaults[.hoverExpandDelay]))
            guard !Task.isCancelled else { return }
            let stillOver = collapsedHoverZoneOnScreen().contains(NSEvent.mouseLocation)
            guard stillOver, state.expansion == .collapsed else {
                islandHoverTask = nil
                return
            }
            state.expansion = .expanded
            islandHoverTask = nil
        }
    }

    private func scheduleIslandCollapse() {
        if islandHoverTask != nil { return }
        islandHoverTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Defaults[.hoverCollapseDelay]))
            guard !Task.isCancelled else { return }
            let stillOver = expandedHoverZoneOnScreen().contains(NSEvent.mouseLocation)
            guard !stillOver, state.expansion == .expanded else {
                islandHoverTask = nil
                return
            }
            state.expansion = .collapsed
            islandHoverTask = nil
        }
    }

    /// 固定窗 frame：始终 expanded 几何（400×166 贴顶居中）。
    /// 展开/收起/媒体宽由窗内 NotchShape 动画，禁止逐帧 setFrame（消顶缝+上下抖）。
    private func fixedWindowFrame(screen: NSScreen? = nil) -> CGRect {
        ScreenNotchDetector.windowFrame(
            for: screen ?? targetScreen,
            expansion: .expanded
        )
    }

    /// 屏幕坐标下的视觉胶囊（hitTest / 拖拽热区同源）
    private func visualFrameOnScreen(screen: NSScreen? = nil) -> CGRect {
        ScreenNotchDetector.visualFrame(
            for: screen ?? targetScreen,
            expansion: state.expansion,
            mediaActive: MediaManager.shared.state.isActive
        )
    }

    /// 同步 contentView hitTest 用的本地视觉 rect
    private func syncHitTestVisualFrame(screen: NSScreen? = nil) {
        let target = screen ?? targetScreen
        let local = ScreenNotchDetector.visualRectInFixedWindow(
            for: target,
            expansion: state.expansion,
            mediaActive: MediaManager.shared.state.isActive
        )
        if let container = panel.contentView as? DragDropContainerView {
            container.visualFrameInView = local
        }
    }

    /// 重新定位窗口（无动画）
    private func reposition() {
        // 启动定位强制主屏（避免启动瞬间鼠标位于已断开的外接屏空间，
        // 导致窗口定位到用户看不到的屏幕上）
        let screen = hasPositioned ? targetScreen : (NSScreen.main ?? targetScreen)
        hasPositioned = true
        applyPanelFrame(fixedWindowFrame(screen: screen))
    }

    /// 是否已完成首次定位
    private var hasPositioned = false

    /// 纠正外部 frame 漂移（位置/尺寸被系统或 hosting 改动时拉回固定窗）
    private func correctFrameDrift() {
        let target = fixedWindowFrame()
        // 容差比较：CGRect 精确比较会因浮点抖动（399.9999 vs 400.0）
        // 造成纠正循环，占满主线程
        let current = panel.frame
        let drifted = abs(current.width - target.width) > 0.5
            || abs(current.height - target.height) > 0.5
            || abs(current.minX - target.minX) > 0.5
            || abs(current.minY - target.minY) > 0.5
        if drifted {
            applyPanelFrame(target)
        } else {
            syncHitTestVisualFrame()
        }
    }

    /// 展开/收起：窗保持固定尺寸；仅同步 hitTest 视觉区。
    /// （历史 Timer 逐帧 setFrame 已废弃——WindowServer 合成抖动致顶缝+上下 bob）
    private func animateWindowSize(to expansion: NotchExpansion) {
        let fixed = fixedWindowFrame()
        if abs(panel.frame.width - fixed.width) > 0.5
            || abs(panel.frame.height - fixed.height) > 0.5
            || abs(panel.frame.minX - fixed.minX) > 0.5
            || abs(panel.frame.minY - fixed.minY) > 0.5 {
            applyPanelFrame(fixed)
        } else {
            syncHitTestVisualFrame()
        }
        // expansion 仅触发 hitTest 同步；内容动画由 NotchView 响应 state
        _ = expansion
    }

    /// 全局拖拽监听（视觉胶囊命中，无透明扩展）
    private var dragMonitor: Any?

    /// 应用窗口 frame 并同步内容尺寸 + hitTest 视觉区
    private func applyPanelFrame(_ frame: NSRect) {
        panel.applyFrame(frame)
        if abs(windowSizeProvider.size.width - frame.size.width) > 0.5
            || abs(windowSizeProvider.size.height - frame.size.height) > 0.5 {
            windowSizeProvider.size = frame.size
        }
        syncHitTestVisualFrame()
    }
}

/// 窗口尺寸提供器（强制 SwiftUI 内容按窗口尺寸布局；macOS 26 hosting
/// 按 fitting 布局导致偏移，NotchView 显式绑定该尺寸解决）
@MainActor
final class WindowSizeProvider: ObservableObject {
    /// 当前窗口内容尺寸（固定窗架构下恒为 expanded 400×166）
    @Published var size: CGSize = CGSize(
        width: AppConfig.expandedWidth,
        height: AppConfig.expandedHeight
    )
}
