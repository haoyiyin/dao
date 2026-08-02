import AppKit
import Foundation

/// 权限管理器：预检与申请系统权限
///
/// 权限项：
/// - 屏幕录制（媒体信息获取需要）
/// - 辅助功能（AppleScript 媒体控制兜底需要）
/// - Apple Events（AppleScript 执行需要，随首次使用自动弹窗）
@MainActor
final class PermissionManager {
    /// 全局单例
    static let shared = PermissionManager()

    // MARK: - 屏幕录制

    /// 是否已授权屏幕录制
    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 申请屏幕录制权限（打开系统设置引导；需用户手动开启）
    func requestScreenRecording() {
        if !hasScreenRecordingPermission {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: - 辅助功能

    /// 是否已授权辅助功能
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// 申请辅助功能权限（系统弹窗引导）
    func requestAccessibility() {
        if !hasAccessibilityPermission {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    // MARK: - 概览

    /// 权限状态汇总
    struct PermissionStatus {
        var screenRecording: Bool
        var accessibility: Bool
    }

    /// 当前全部权限状态
    var status: PermissionStatus {
        PermissionStatus(
            screenRecording: hasScreenRecordingPermission,
            accessibility: hasAccessibilityPermission
        )
    }
}
