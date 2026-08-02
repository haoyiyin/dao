import Darwin
import Foundation

/// CPU 使用率采样器
///
/// 基于 mach host_processor_info（PROCESSOR_CPU_LOAD_INFO）：
/// 两次采样间的 CPU_TICK 差值 / 总 tick 差值 = 使用率。
enum CPUMonitor {
    /// CPU tick 快照（全部核心聚合）
    private struct CPUTickSnapshot {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64

        var total: UInt64 { user + system + idle + nice }
    }

    private static var lastSnapshot: CPUTickSnapshot?

    /// 采样 CPU 使用率（0-1）；首次调用返回 nil（建立基线，需要两次采样）
    static func sample() -> Double? {
        var processorInfo: processor_info_array_t?
        var processorCount: mach_msg_type_number_t = 0
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info = processorInfo else {
            return nil
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        // 汇总所有 CPU 核心的 tick（数组按 CPU_STATE_MAX 步长排列）
        let coreCount = Int(infoCount) / Int(CPU_STATE_MAX)
        guard coreCount > 0 else { return nil }
        var total = CPUTickSnapshot(user: 0, system: 0, idle: 0, nice: 0)
        for core in 0..<coreCount {
            let base = core * Int(CPU_STATE_MAX)
            total.user += UInt64(info[base + Int(CPU_STATE_USER)])
            total.system += UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            total.idle += UInt64(info[base + Int(CPU_STATE_IDLE)])
            total.nice += UInt64(info[base + Int(CPU_STATE_NICE)])
        }

        guard let last = lastSnapshot else {
            lastSnapshot = total
            return nil
        }
        lastSnapshot = total

        let totalDelta = total.total - last.total
        guard totalDelta > 0 else { return nil }
        let busyDelta = (total.total - total.idle) - (last.total - last.idle)
        return Double(busyDelta) / Double(totalDelta)
    }

    /// 重置基线（采样器重启时调用，避免脏差值）
    static func reset() {
        lastSnapshot = nil
    }
}
