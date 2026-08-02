import SwiftUI

/// 可拖拽媒体进度条
///
/// - 拖动中显示拖拽预览位置（不发送 seek）
/// - 松手时回调目标时间，随后延迟复位（等待流状态更新，避免进度跳变）
/// - 拖拽命中区域加高（16pt），便于操作
struct MediaProgressBar: View {
    /// 当前进度（秒）
    let progress: TimeInterval
    /// 总时长（秒，0 = 未知）
    let duration: TimeInterval
    /// 拖拽位置绑定（外部状态，nil = 未拖拽）
    @Binding var dragPosition: TimeInterval?
    /// 松手回调（目标秒）
    var onSeek: (TimeInterval) -> Void

    /// 拖拽复位任务（seek 后延迟清除拖拽位置）
    @State private var resetTask: Task<Void, Never>?

    private var effectiveProgress: TimeInterval {
        dragPosition ?? progress
    }

    private var fraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(effectiveProgress, 0), duration) / duration)
    }

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // 轨道
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)
                    // 已播放
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(4, width * fraction), height: 4)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width))
            }
            .frame(height: 16)

            HStack {
                Text(format(effectiveProgress))
                Spacer()
                Text(format(duration))
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: - 拖拽

    /// 拖拽手势：换算拖动位置 → 秒，松手时回调并延迟复位
    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard duration > 0 else { return }
                let clamped = min(max(value.location.x, 0), width)
                let seconds = TimeInterval(clamped / width) * duration
                dragPosition = seconds
            }
            .onEnded { _ in
                guard let target = dragPosition, duration > 0 else {
                    dragPosition = nil
                    return
                }
                onSeek(target)
                // 保持目标位置一段时间（等流状态更新），再复位避免跳变
                resetTask?.cancel()
                resetTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    dragPosition = nil
                }
            }
    }

    // MARK: - 格式化

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
