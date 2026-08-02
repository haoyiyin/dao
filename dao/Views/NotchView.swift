import SwiftUI

/// 灵动岛主视图
///
/// - 固定窗 400×166：折叠/展开由窗内 NotchShape+内容尺寸动画（消顶缝/上下抖）
/// - 悬停展开/收起：带可配置延迟与防抖（快速移入移出不抖动）
/// - 点击可切换状态；点击后 1 秒内抑制悬停展开，避免"点收被悬停顶开"
/// - 拖放接收：拖拽进入立即展开并高亮，接收后显示结果提示
struct NotchView: View {
    @ObservedObject var state: NotchExpansionState

    /// 窗口尺寸（macOS 26 hosting 内容按 fitting 布局，显式 frame 强制对齐窗口）
    @EnvironmentObject private var windowSize: WindowSizeProvider
    /// 语言（语言切换时整树重建，强制刷新全部文案）
    @EnvironmentObject private var language: LanguageManager
    /// 媒体（收起态宽度 185↔265 随会话变化）
    @EnvironmentObject private var mediaManager: MediaManager

    /// 展开态抽屉选择（拖放文件时自动切换到传输）
    @State private var selectedDrawer: ExpandedView.DrawerTab = .media

    /// 提示自动消失任务
    @State private var toastTask: Task<Void, Never>?
    /// 拖拽悬停高亮
    @State private var isDropTarget = false
    /// 拖放结果提示
    @State private var dropToast: String?

    private var isExpanded: Bool { state.expansion == .expanded }

    /// 固定窗架构：内容/外形动画统一曲线（与历史 AppKit 0.4s ease 视觉一致）
    static let islandAnimation: Animation = .timingCurve(0.22, 1, 0.36, 1, duration: 0.4)

    /// 视觉胶囊尺寸（窗恒 400×166；收起只缩 shape/内容，不改窗）
    private var visualSize: CGSize {
        if isExpanded {
            return windowSize.size
        }
        let width = mediaManager.state.isActive
            ? AppConfig.collapsedWidth : AppConfig.notchWidth
        let height = ScreenNotchDetector.collapsedHeight(
            for: ScreenNotchDetector.currentScreen()
        )
        return CGSize(width: width, height: height)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 黑底外形：仅此层 + mask 跟 visualSize 动画（岛外形长大）
            NotchShape()
                .fill(Color.black)
                .frame(width: visualSize.width, height: visualSize.height)
                .frame(
                    width: windowSize.size.width,
                    height: windowSize.size.height,
                    alignment: .top
                )
                .animation(Self.islandAnimation, value: state.expansion)
                .animation(Self.islandAnimation, value: mediaManager.state.isActive)

            // 内容：展开态永远全窗布局，禁止跟 expansion 做 frame 插值
            // 根级 .animation(value: expansion) 会让插入的 ExpandedView 从胶囊尺寸
            // 插到全窗 → 左侧封面先冲左下，岛外形慢半拍
            contentLayer
                .frame(
                    width: windowSize.size.width,
                    height: windowSize.size.height,
                    alignment: .top
                )
                .mask(
                    NotchShape()
                        .frame(width: visualSize.width, height: visualSize.height)
                        .frame(
                            width: windowSize.size.width,
                            height: windowSize.size.height,
                            alignment: .top
                        )
                        .animation(Self.islandAnimation, value: state.expansion)
                        .animation(Self.islandAnimation, value: mediaManager.state.isActive)
                )
        }
        .overlay(alignment: .top) {
            // 拖放结果提示
            if let dropToast {
                Text(dropToast)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .padding(.top, 64)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // 语言变化 → 整树重建（确保所有视图文案即时切换）
        .id(language.language)
        .animation(.easeOut(duration: 0.15), value: isDropTarget)
        .animation(.easeInOut(duration: 0.2), value: dropToast)
        // 根 frame 恒=固定窗尺寸（hosting 对齐）
        // 悬停展开/收起由 NotchWindowController AppKit mouseMoved 判定视觉胶囊
        // （透明窗 + SwiftUI onContinuousHover 会误触固定窗下方透明区）
        .frame(width: windowSize.size.width, height: windowSize.size.height)
        // 拖放接收由 AppKit 容器（DragDropContainerView）处理——
        // SwiftUI onDrop 对文本类文件（MD）只给内容类型拿不到文件名
        .onReceive(NotificationCenter.default.publisher(for: .notchDragEntered)) { _ in
            isDropTarget = true
            selectedDrawer = .transfer
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchDragDropped)) { note in
            isDropTarget = false
            let count = (note.userInfo?["count"] as? Int) ?? 0
            showDropResult(count: count)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchDragExited)) { _ in
            // 拖拽离开/取消：清除高亮（否则蓝色描边残留）
            isDropTarget = false
        }
    }

    /// 内容层：展开=全窗 ExpandedView（布局不随岛缩放）；收起=胶囊 CollapsedView
    /// 不用 islandAnimation 绑 expansion——否则插入的 ExpandedView 会从胶囊尺寸插值，
    /// 左侧封面先冲左下、岛外形慢半拍。
    @ViewBuilder
    private var contentLayer: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                ExpandedView(selectedDrawer: $selectedDrawer)
                    .frame(
                        width: windowSize.size.width,
                        height: windowSize.size.height
                    )
                    // 展开内容只淡入，frame 不参与 island 曲线插值
                    .transition(.opacity)
            } else {
                CollapsedView()
                    .frame(width: visualSize.width, height: visualSize.height)
                    .frame(
                        width: windowSize.size.width,
                        height: windowSize.size.height,
                        alignment: .top
                    )
                    // 媒体宽 185↔265 时收起内容跟外形
                    .animation(Self.islandAnimation, value: mediaManager.state.isActive)
                    .transition(.identity)
            }
        }
        // 仅驱动 if 切换的 opacity；时长短于外形，避免封面抢跑
        .animation(.easeOut(duration: 0.18), value: isExpanded)
    }

    // MARK: - 拖放结果

    /// 显示接收结果提示（2 秒后自动消失；双语）
    private func showDropResult(count: Int) {
        if count > 0 {
            dropToast = count == 1
                ? language.text("已接收 1 项", "Received 1 item")
                : language.text("已接收 \(count) 项", "Received \(count) items")
        } else {
            dropToast = language.text("无法接收该项目", "Cannot accept this item")
        }
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            dropToast = nil
        }
    }

}
