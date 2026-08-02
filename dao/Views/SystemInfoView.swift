import SwiftUI

/// 系统信息视图（条状图样式：CPU / 内存 / 磁盘）
///
/// - 默认直接显示条状图（进度条 + 数值），无折叠/展开切换
/// - 数据由 SystemMonitor 每 1.5s 发布
struct SystemInfoView: View {
    @EnvironmentObject private var systemMonitor: SystemMonitor

    private var snapshot: SystemSnapshot { systemMonitor.snapshot }

    var body: some View {
        // 内容按自身高度顶部固定（不随窗口高度移动）：
        // maxHeight: .infinity 会让内容区随窗口生长动画缓慢下移（实测 7.5pt），
        // 表现为展开时"上下抖动一下"；底部空白由 NotchView 层黑底覆盖
        SystemDetailView(snapshot: snapshot)
            .padding(10)
    }
}
