import Foundation

/// 磁盘使用率采样器
///
/// 基于卷的 resourceValues（volumeTotalCapacityKey / volumeAvailableCapacityKey），
/// 默认采样启动盘（/）。
enum DiskMonitor {
    /// 采样磁盘信息，返回 (used, total) 字节
    static func sample() -> (used: UInt64, total: UInt64)? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]),
        let total = values.volumeTotalCapacity,
        let available = values.volumeAvailableCapacity
        else { return nil }

        let used = max(0, total - available)
        return (UInt64(used), UInt64(total))
    }
}
