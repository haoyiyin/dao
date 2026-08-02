import Defaults
import Foundation

/// 界面语言
enum AppLanguage: String, CaseIterable, Identifiable {
    case zh = "zh-Hans"
    case en = "en"

    var id: String { rawValue }

    /// 显示名称
    var displayName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    /// 跟随系统首选语言：`zh*` → 中文，其余 → 英文
    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return preferred.hasPrefix("zh") ? .zh : .en
    }
}

/// 语言管理器（切换时所有视图即时刷新）
@MainActor
final class LanguageManager: ObservableObject {
    /// 全局单例
    static let shared = LanguageManager()

    /// 当前语言
    @Published var language: AppLanguage

    private init() {
        language = AppLanguage(rawValue: Defaults[.language]) ?? .systemDefault
    }

    /// 切换语言（zh ↔ en 循环）
    func toggle() {
        setLanguage(language == .zh ? .en : .zh)
    }

    /// 设置语言并持久化
    func setLanguage(_ newLanguage: AppLanguage) {
        language = newLanguage
        Defaults[.language] = newLanguage.rawValue
    }

    /// 双语取词
    func text(_ zh: String, _ en: String) -> String {
        language == .zh ? zh : en
    }
}
