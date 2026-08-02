import IOKit.ps
import Foundation

/// 电池状态采样器
///
/// 基于 IOKit 电源管理 API（IOPSCopyPowerSourcesInfo，公开框架）：
/// 电量百分比、充电状态、剩余时间（无电池设备返回 nil，UI 自动隐藏）。
enum BatteryMonitor {
    /// 电池采样结果
    struct BatterySample {
        let level: Double
        let isCharging: Bool
        let timeRemaining: TimeInterval?
    }

    /// 采样电池信息（无电池设备返回 nil）
    static func sample() -> BatterySample? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [AnyObject]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            // 仅处理内部电池（UPS 等跳过）
            let type = description[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

            // 电量百分比
            var level: Double?
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 {
                level = Double(current) / Double(max)
            }

            // 剩余时间
            var timeRemaining: TimeInterval?
            if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes >= 0,
               minutes != Int(kIOPSTimeRemainingUnknown) {
                timeRemaining = TimeInterval(minutes * 60)
            }

            return BatterySample(level: level ?? 0, isCharging: isCharging, timeRemaining: timeRemaining)
        }
        return nil
    }
}
