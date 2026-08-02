import Darwin
import Foundation

/// 网络速率采样器
///
/// 基于 getifaddrs 枚举所有 AF_LINK 接口的字节计数：
/// 两次采样间的 (rx/tx 字节差) / 采样间隔 = 速率（字节/秒）。
/// 过滤 lo0（回环）与无 IP 的虚拟接口。
enum NetworkMonitor {
    /// 接口字节快照
    private struct InterfaceSnapshot {
        var rxBytes: UInt64
        var txBytes: UInt64
    }

    /// 全部活跃接口的聚合快照
    private struct AggregateSnapshot {
        var rxBytes: UInt64
        var txBytes: UInt64
    }

    private static var lastSnapshot: AggregateSnapshot?

    /// 采样上下行速率（字节/秒）；首次调用返回 nil（需要两次采样）
    static func sample() -> (upload: Double, download: Double)? {
        guard let current = collect() else { return nil }
        guard let last = lastSnapshot else {
            lastSnapshot = current
            return nil
        }
        lastSnapshot = current
        // 计数器回绕保护（UInt64 溢出几乎不可能，差值取安全下溢）
        let rxDelta = current.rxBytes >= last.rxBytes ? current.rxBytes - last.rxBytes : 0
        let txDelta = current.txBytes >= last.txBytes ? current.txBytes - last.txBytes : 0
        return (
            upload: Double(txDelta),
            download: Double(rxDelta)
        )
    }

    /// 重置基线
    static func reset() {
        lastSnapshot = nil
    }

    /// 收集所有非回环接口的字节计数
    private static func collect() -> AggregateSnapshot? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let interface = current.pointee
            // 仅统计 AF_LINK 接口（有物理字节计数）
            guard interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let name = String(cString: interface.ifa_name)
            // 过滤回环与常见虚拟接口
            guard name != "lo0",
                  !name.hasPrefix("awdl"),
                  !name.hasPrefix("llw"),
                  !name.hasPrefix("utun"),
                  !name.hasPrefix("ipsec"),
                  !name.hasPrefix("gif"),
                  !name.hasPrefix("stf")
            else { continue }

            guard let data = interface.ifa_data else { continue }
            let networkData = data.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(networkData.ifi_ibytes)
            tx += UInt64(networkData.ifi_obytes)
        }
        return AggregateSnapshot(rxBytes: rx, txBytes: tx)
    }
}
