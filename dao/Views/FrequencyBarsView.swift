import SwiftUI

/// 动态频率线图标（音频频谱动画）
///
/// 播放中：若干竖条随时间起伏（正弦叠加伪随机，平滑变化）
/// 暂停/未播放：静止为低矮条
struct FrequencyBarsView: View {
    /// 是否播放中（false 时静止）
    let isPlaying: Bool

    /// 竖条数量
    private let barCount = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying)) { context in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 3, height: barHeight(at: context.date, index: index))
                        // 高度平滑过渡（每 tick 动画而非跳变，频谱更柔滑）
                        .animation(.easeInOut(duration: 0.12), value: barHeight(at: context.date, index: index))
                }
            }
            .frame(height: 16, alignment: .center)
        }
    }

    /// 竖条高度：基于时间与索引的正弦叠加（4-16pt）
    private func barHeight(at date: Date, index: Int) -> CGFloat {
        guard isPlaying else { return 4 }
        let time = date.timeIntervalSinceReferenceDate
        let phase = time * 2.5 + Double(index) * 1.7
        // 两个不同频率正弦叠加 → 起伏不规则，接近真实频谱
        let wave = (sin(phase) + sin(phase * 0.53 + Double(index))) / 2
        return 4 + (wave + 1) * 6
    }
}
