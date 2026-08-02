import Defaults
import SwiftUI

/// 设置页内容（灵动岛内打开；顶栏按钮由 ExpandedView 承载）
///
/// 仅保留默认播放器选择。
struct SettingsDrawerView: View {
    @EnvironmentObject private var language: LanguageManager

    /// 默认播放器（Defaults 持久化）
    @Default(.defaultPlayer) private var defaultPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        .padding(10)
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
