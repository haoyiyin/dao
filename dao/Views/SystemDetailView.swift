import SwiftUI

/// 系统信息详情视图：各指标进度条 + 数值明细
struct SystemDetailView: View {
    @EnvironmentObject private var language: LanguageManager

    let snapshot: SystemSnapshot

    var body: some View {
        VStack(spacing: 10) {
            if snapshot.cpuUsage != nil {
                detailRow(
                    icon: SystemMetric.cpu.icon,
                    title: SystemMetric.cpu.displayName,
                    value: Formatters.percent(snapshot.cpuUsage),
                    fraction: snapshot.cpuUsage
                )
            }
            if let used = snapshot.memoryUsed, let total = snapshot.memoryTotal {
                detailRow(
                    icon: SystemMetric.memory.icon,
                    title: SystemMetric.memory.displayName,
                    value: "\(Formatters.bytes(used)) / \(Formatters.bytes(total))",
                    fraction: Double(used) / Double(total)
                )
            }
            if let used = snapshot.diskUsed, let total = snapshot.diskTotal {
                detailRow(
                    icon: SystemMetric.disk.icon,
                    title: SystemMetric.disk.displayName,
                    value: "\(Formatters.bytes(used)) / \(Formatters.bytes(total))",
                    fraction: Double(used) / Double(total)
                )
            }
        }
    }


    /// 单行指标：图标 + 名称 + 进度条 + 数值
    private func detailRow(icon: String, title: String, value: String, fraction: Double?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 16)

            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 30, alignment: .leading)

            GeometryReader { _ in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    if let fraction, fraction.isFinite {
                        Capsule()
                            .fill(Color.accentColor)
                            // scaleEffect 是渲染变换（不触发布局重排）：
                            // 窗口生长动画中 GeometryReader 每帧重算 frame(width:)
                            // 会与窗口 Timer 竞争主线程导致掉帧抖动
                            .scaleEffect(x: min(max(fraction, 0), 1), anchor: .leading)
                            .animation(.easeOut(duration: 0.25), value: fraction)
                    }
                }
            }
            .frame(height: 5)

            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .frame(minWidth: 130, alignment: .trailing)
                // 数字平滑滚动（等宽字体 + 固定宽度，无布局变化）
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: value)
        }
        .frame(height: 20)
    }
}
