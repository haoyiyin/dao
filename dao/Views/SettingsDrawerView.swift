import Defaults
import LaunchAtLogin
import SwiftUI

/// 设置页（灵动岛内打开）
///
/// 布局：
/// - 顶部行：自启动 / 语言 / 退出 / 关闭
/// - 默认播放器选择
struct SettingsDrawerView: View {
    @EnvironmentObject private var language: LanguageManager
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

    /// 默认播放器（Defaults 持久化）
    @Default(.defaultPlayer) private var defaultPlayer

    /// 关闭设置回调（由 ExpandedView 注入）
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 顶部行：自启动（闪电）/ 语言（中/EN）/ 退出 / 关闭 —— 同一行
            // （设置页在 ScrollView 内：ClickableView 不触发，用 onTapGesture + onHover）
            HStack(spacing: 4) {
                // 自启动（闪电图标：点击高亮=开启，点击灭掉=关闭；悬停显示"开机启动"）
                SettingsIconButton(
                    symbol: launchAtLogin.isEnabled ? "bolt.fill" : "bolt",
                    isActive: launchAtLogin.isEnabled,
                    help: language.text("开机启动", "Launch at login")
                ) {
                    launchAtLogin.isEnabled.toggle()
                }

                // 语言（"中"/"EN" 文字图标：点击切换中英文；hover 聚焦）
                LanguageToggleIcon(language: language.language) {
                    language.toggle()
                }

                Spacer()

                // 退出（电源图标）
                SettingsIconButton(
                    symbol: "power",
                    help: language.text("退出", "Quit")
                ) {
                    NSApp.terminate(nil)
                }

                // 关闭设置（xmark）
                SettingsIconButton(
                    symbol: "xmark",
                    help: language.text("关闭", "Close")
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        onClose()
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.15))

            // 默认播放器选择（无媒体播放时点击播放打开的应用）
            Text(language.text("默认播放器", "Default player"))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(DefaultPlayerOption.allCases) { option in
                    PlayerOptionChip(
                        name: option.displayName,
                        isSelected: defaultPlayer == option.rawValue
                    ) {
                        defaultPlayer = option.rawValue
                    }
                }
            }
        }
        // 内容按自身高度顶部固定（不随窗口高度移动，避免展开动画中下移抖动）
        .padding(10)
    }
}

/// 设置页图标按钮（ScrollView 内使用：onTapGesture + onHover，ClickableView 在 ScrollView 内不触发）
private struct SettingsIconButton: View {
    /// SF Symbol（与 text 二选一）
    var symbol: String?
    /// 文字图标（如"中"/"EN"）
    var text: String?
    /// 激活态（常亮高亮）
    var isActive = false
    /// 悬停提示
    var help: String
    /// 点击回调
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
            } else if let text {
                Text(text)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
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

/// 语言切换图标（"中"/"EN"，hover 聚焦）
private struct LanguageToggleIcon: View {
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

/// 默认播放器选项胶囊（hover 聚焦）
private struct PlayerOptionChip: View {
    let name: String
    let isSelected: Bool
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Text(name)
            .font(.system(size: 9))
            .foregroundStyle(isSelected ? Color.black : .white.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.white
                        : (isHovering ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                )
            )
            .contentShape(Capsule())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
            .onTapGesture(perform: action)
    }
}
