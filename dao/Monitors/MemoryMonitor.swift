import Darwin
import Foundation

/// 内存使用率采样器
///
/// 基于 host_statistics64（HOST_VM_INFO64）：
/// 已用 = 总物理内存 - (free + 压缩内存可回收部分近似)。
/// 与活动监视器口径：app memory ≈ active + wired + compressed（近似）。
enum MemoryMonitor {
    /// 采样内存信息，返回 (used, total) 字节
    static func sample() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory
        // 已用 = active + wired + compressed（活动监视器口径的近似）
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        return (min(used, total), total)
    }
}
