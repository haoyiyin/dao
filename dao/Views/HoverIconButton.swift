import SwiftUI

/// 可悬停图标按钮（hover 聚焦高亮 + 点击反馈）
///
/// - 悬停：SwiftUI onHover 驱动（ClickableView 无 tracking，不截获 hover 事件）
/// - 激活态（isActive）：常亮高亮（如自启动开启）
/// - 点击：ClickableView（AppKit mouseDown，非激活面板点击稳定）
struct HoverIconButton: View {
    /// SF Symbol
    let symbol: String
    /// 按钮尺寸（图标约为其 55%）
    var size: CGFloat = 22
    /// 激活态（常亮高亮）
    var isActive: Bool = false
    /// 悬停提示文案
    var help: String = ""
    /// 悬停状态变化回调（如抽屉悬停切换）
    var onHoverChange: ((Bool) -> Void)?
    /// 点击回调
    var action: () -> Void

    /// 悬停状态
    @State private var isHovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(
                isActive || isHovering ? Color.white : Color.white.opacity(0.55)
            )
            .frame(width: size, height: size)
            .scaleEffect(isHovering ? 1.12 : 1)
            .background(
                Circle().fill(
                    isActive
                        ? Color.white.opacity(0.3)
                        : (isHovering ? Color.white.opacity(0.4) : Color.white.opacity(0.05))
                )
            )
            .contentShape(Circle())
            .overlay(
                // hover 由 AppKit tracking 驱动（SwiftUI hover 在非激活面板子视图不可靠）
                ClickableView(perform: action) { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHovering = hovering
                    }
                    onHoverChange?(hovering)
                }
            )
            .help(help)
    }
}
