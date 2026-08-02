import Defaults
import Foundation

/// 系统快照模型（采样器输出的不可变数据）
struct SystemSnapshot: Equatable {
    /// CPU 使用率（0-1）
    var cpuUsage: Double?
    /// 内存使用率（0-1）
    var memoryUsage: Double?
    /// 内存已用（字节）
    var memoryUsed: UInt64?
    /// 内存总量（字节）
    var memoryTotal: UInt64?
    /// 磁盘已用（字节）
    var diskUsed: UInt64?
    /// 磁盘总量（字节）
    var diskTotal: UInt64?
    /// 网络上行速率（字节/秒）
    var networkUpload: Double?
    /// 网络下行速率（字节/秒）
    var networkDownload: Double?
    /// 电池电量（0-1）
    var batteryLevel: Double?
    /// 是否在充电
    var isCharging: Bool?
    /// 电池剩余时间（秒）
    var batteryTimeRemaining: TimeInterval?
    /// 采样时间
    var timestamp = Date()
}

/// 系统监控项类型（显示项/顺序可配置）
enum SystemMetric: String, CaseIterable, Codable, Identifiable {
    case cpu
    case memory
    case disk

    var id: String { rawValue }

    /// 显示名称（按当前语言；nonisolated：从 Defaults 直接读取）
    nonisolated var displayName: String {
        let isZh = Defaults[.language] == "zh-Hans"
        switch self {
        case .cpu: return "CPU"
        case .memory: return isZh ? "内存" : "Memory"
        case .disk: return isZh ? "磁盘" : "Disk"
        }
    }

    /// 显示图标
    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        }
    }
}
