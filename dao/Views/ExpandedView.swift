import SwiftUI

/// 展开态容器：顶部刘海延续 + 横轴抽屉（媒体 / 传输 / 系统）
///
/// - 媒体抽屉：无论播放与否都显示媒体控制（无媒体时显示开始播放入口）
/// - 传输抽屉：AirDrop 正方形 + 文件暂存矩形
/// - 系统抽屉：系统信息（指标胶囊 + 详情）
/// - 背景纯黑；右上角设置图标（替代菜单栏托盘）
struct ExpandedView: View {
    /// 抽屉类型（设置不进抽屉，保持在右上角齿轮）
    enum DrawerTab: String, CaseIterable, Identifiable {
        case media
        case transfer
        case system

        var id: String { rawValue }

        var title: String {
            switch self {
            case .media: return "媒体"
            case .transfer: return "传输"
            case .system: return "系统"
            }
        }

        var icon: String {
            switch self {
            case .media: return "music.note"
            case .transfer: return "arrow.up.arrow.down"
            case .system: return "gauge.with.dots.needle.bottom.50percent"
            }
        }
    }

    /// 当前选中抽屉（由 NotchView 持有，拖放文件时自动切换到传输）
    @Binding var selectedDrawer: DrawerTab

    /// 是否显示设置面板（右上角齿轮控制，不进抽屉菜单）
    @State private var showSettings = false

    /// 刘海延续高度（与收起态一致，底部不越过摄像头底线）
    private var notchPillHeight: CGFloat {
        ScreenNotchDetector.collapsedHeight(for: ScreenNotchDetector.currentScreen())
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                // 设置全屏页：覆盖整个灵动岛
                settingsFullScreen
            } else {
                // 顶部行：抽屉图标（左）+ 刘海 pill（中）+ 设置图标（右），同一行
                topBarRow

                // 抽屉内容
                drawerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 黑底外形由 NotchView 层统一绘制；避免双层 shape 与固定窗尺寸动画冲突
        .overlay(alignment: .topTrailing) {
            // 设置图标（保留 overlay 用于设置全屏页时显示）
            EmptyView()
        }
    }

    /// 设置全屏页（覆盖抽屉栏；内容超高时内部滚动）
    private var settingsFullScreen: some View {
        ScrollView(showsIndicators: false) {
            SettingsDrawerView {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showSettings = false
                }
            }
            .padding(12)
        }
    }

    // MARK: - 顶部行（图标 + 刘海 + 设置，同一行）

    private var topBarRow: some View {
        HStack(spacing: 0) {
            // 左：抽屉图标组（仅图标，小尺寸）
            HStack(spacing: 5) {
                ForEach(DrawerTab.allCases) { tab in
                    drawerIconButton(tab)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            // 中：刘海 pill（与收起态胶囊同高，视觉无缝）
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
                .frame(width: AppConfig.notchWidth, height: notchPillHeight)

            // 右：设置图标（与抽屉图标同一行）
            HStack {
                Spacer()
                gearButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .frame(height: notchPillHeight)
    }

    /// 抽屉图标按钮（小图标，悬停自动切换；onTapGesture：非激活面板 Button 不触发）
    /// 抽屉图标按钮（小图标，hover 聚焦高亮；悬停自动切换菜单）
    private func drawerIconButton(_ tab: DrawerTab) -> some View {
        HoverIconButton(
            symbol: tab.icon,
            size: 24,
            isActive: selectedDrawer == tab,
            onHoverChange: { hovering in
                // 悬停自动切换菜单
                if hovering, selectedDrawer != tab {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedDrawer = tab
                    }
                }
            },
            action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedDrawer = tab
                }
            }
        )
    }

    /// 设置图标按钮（hover 聚焦高亮；点击切换设置全屏页）
    private var gearButton: some View {
        HoverIconButton(
            symbol: "gearshape.fill",
            size: 24,
            isActive: showSettings
        ) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showSettings.toggle()
            }
        }
    }


    @ViewBuilder
    private var drawerContent: some View {
        switch selectedDrawer {
        case .media: mediaContent
        case .transfer: transferContent
        case .system: systemContent
        }
    }

    /// 媒体抽屉：无论播放与否都显示媒体控制（无媒体时信息为空，点击播放打开默认播放器）
    private var mediaContent: some View {
        MediaControlView()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// 传输抽屉：AirDrop 正方形 + 文件暂存矩形（底部严格对齐、居中）
    private var transferContent: some View {
        HStack(alignment: .top, spacing: 12) {
            AirDropView()
                .frame(width: 90, height: 90)
            ShelfView()
                .frame(maxWidth: .infinity)
        }
        // 外层固定高度：两个区域底部严格一致
        .frame(height: 90, alignment: .top)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// 系统抽屉：系统信息（条状图；居中，超高滚动）
    private var systemContent: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                SystemInfoView()
                    .padding(12)
                    .frame(minHeight: geo.size.height, alignment: .center)
            }
        }
    }
}
