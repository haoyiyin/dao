import AppKit
import Foundation

/// 应用内通知名称
extension Notification.Name {
    /// 显示/隐藏灵动岛（设置窗口按钮触发）
    static let toggleNotchVisibility = Notification.Name("toggleNotchVisibility")
    /// 拖拽热区进入（展开并切传输抽屉）
    static let notchDragEntered = Notification.Name("notchDragEntered")
    /// 拖放完成（显示结果提示）
    static let notchDragDropped = Notification.Name("notchDragDropped")
    /// 拖拽离开/取消（清除高亮）
    static let notchDragExited = Notification.Name("notchDragExited")
}

/// 通用格式化工具
enum Formatters {
    /// 百分比（0-1 → "42%"）
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    /// 字节 → 人类可读（"1.2 GB"）
    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    /// 字节/秒 → 人类可读速率（"3.4 MB/s"）
    static func speed(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond.isFinite else { return "--" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    /// 秒 → "1:23:45" / "23:45"
    static func clock(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// 电池剩余时间（"2 小时 15 分"）
    static func batteryTime(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours) 小时 \(minutes) 分"
        }
        return "\(minutes) 分"
    }
}
