import SwiftUI

/// 收起态：纯黑胶囊（与摄像头融为一体）
///
/// - 无媒体会话：与摄像头同宽（185），纯黑 + 细描边圆角，无内容
/// - 有媒体会话：向两侧延伸（265），左 = 媒体图标，右 = 动态频率线
///   （播放中频率线动态，暂停时静态；窗口宽度由 NotchWindowController 动画驱动）
struct CollapsedView: View {
    @EnvironmentObject private var mediaManager: MediaManager

    private var state: MediaState { mediaManager.state }
    private var hasMediaSession: Bool { state.isActive }

    var body: some View {
        GeometryReader { _ in
            // 左右区固定宽度 + 中段固定摄像头宽度 → 理想尺寸精确 = 窗口尺寸
            // （避免 hosting 按理想尺寸居中渲染导致偏移）
            let sideWidth: CGFloat = 40

            HStack(spacing: 0) {
                // 左段：摄像头左侧可见区（媒体图标）
                leftContent
                    .frame(width: sideWidth)

                // 中段：摄像头区域（透明占位——背景 NotchShape 已覆盖纯黑，
                // 若用直角矩形会盖住背景的左右下角圆角）
                Color.clear
                    .frame(width: AppConfig.notchWidth)

                // 右段：摄像头右侧可见区（频率线）
                rightContent
                    .frame(width: sideWidth)
            }
        }
        // 黑底外形由 NotchView 层统一绘制并做尺寸动画；此处不再叠第二层 NotchShape
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: - 左段内容

    @ViewBuilder
    private var leftContent: some View {
        if hasMediaSession {
            // padding 在前、frame 在后（顺序颠倒会导致布局溢出偏移）
            // padding 12：内容向中间靠拢，避免太贴屏幕边缘
            mediaIcon
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 右段内容

    @ViewBuilder
    private var rightContent: some View {
        if hasMediaSession {
            // 播放中动态、暂停时静态（trailing 12：向中间靠拢）
            FrequencyBarsView(isPlaying: state.isPlaying)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// 媒体图标：封面缩略（有封面时）或音符占位
    @ViewBuilder
    private var mediaIcon: some View {
        if let data = state.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
