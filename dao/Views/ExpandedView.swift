import LaunchAtLogin
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

    @EnvironmentObject private var language: LanguageManager
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

    /// 是否显示设置面板（右上角齿轮控制，不进抽屉菜单）
    @State private var showSettings = false

    /// 刘海延续高度（与收起态一致，底部不越过摄像头底线）
    private var notchPillHeight: CGFloat {
        ScreenNotchDetector.collapsedHeight(for: ScreenNotchDetector.currentScreen())
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                // 顶栏：与菜单栏/刘海同高，承载设置快捷按钮
                settingsTopBarRow
                // 设置内容（默认播放器等）
                settingsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    }

    /// 设置内容区（顶栏以下；超高时滚动）
    private var settingsContent: some View {
        ScrollView(showsIndicators: false) {
            SettingsDrawerView()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
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

    /// 设置态顶栏：与 `topBarRow` 同高，贴菜单栏/刘海
    private var settingsTopBarRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                // 自启动
                SettingsTopIconButton(
                    symbol: launchAtLogin.isEnabled ? "bolt.fill" : "bolt",
                    isActive: launchAtLogin.isEnabled,
                    help: language.text("开机启动", "Launch at login")
                ) {
                    launchAtLogin.isEnabled.toggle()
                }
                // 语言
                SettingsLanguageToggle(language: language.language) {
                    language.toggle()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
                .frame(width: AppConfig.notchWidth, height: notchPillHeight)

            HStack(spacing: 5) {
                Spacer()
                SettingsTopIconButton(
                    symbol: "power",
                    help: language.text("退出", "Quit")
                ) {
                    NSApp.terminate(nil)
                }
                SettingsTopIconButton(
                    symbol: "xmark",
                    help: language.text("关闭", "Close")
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showSettings = false
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .frame(height: notchPillHeight)
    }

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

// MARK: - 设置顶栏控件

/// 设置顶栏图标按钮（与抽屉 HoverIconButton 同尺寸，贴刘海行）
private struct SettingsTopIconButton: View {
    var symbol: String
    var isActive = false
    var help: String
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isActive || isHovering ? Color.white : Color.white.opacity(0.6))
            .frame(width: 24, height: 24)
            .background(
                Circle().fill(
                    isActive
                        ? Color.white.opacity(0.25)
                        : (isHovering ? Color.white.opacity(0.16) : Color.white.opacity(0.05))
                )
            )
            .contentShape(Circle())
            .onContinuousHover { phase in
                let hovering: Bool
                switch phase {
                case .active: hovering = true
                case .ended: hovering = false
                }
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
            .onTapGesture(perform: action)
            .help(help)
    }
}

/// 设置顶栏语言切换（"中"/"EN"）
private struct SettingsLanguageToggle: View {
    let language: AppLanguage
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            Circle().fill(isHovering ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
            Text(language == .zh ? "中" : "EN")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: 24, height: 24)
        .contentShape(Circle())
        .onContinuousHover { phase in
            let hovering: Bool
            switch phase {
            case .active: hovering = true
            case .ended: hovering = false
            }
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .onTapGesture(perform: action)
        .help(language == .zh ? "切换 English" : "切换中文")
    }
}
