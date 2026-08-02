import Defaults
import Foundation

/// 应用设置（Defaults 持久化键定义）
///
/// 设置项在 M5 设置页中暴露 UI，此处先行定义键与默认值。
extension Defaults.Keys {
    /// 系统监控显示项与顺序（默认全量，按枚举声明顺序）
    static let systemMetricsOrder = Key<[String]>(
        "systemMetricsOrder",
        default: SystemMetric.allCases.map(\.rawValue)
    )

    /// 悬停展开延迟（秒）
    static let hoverExpandDelay = Key<Double>("hoverExpandDelay", default: AppConfig.hoverExpandDelay)

    /// 移出收起延迟（秒）
    static let hoverCollapseDelay = Key<Double>("hoverCollapseDelay", default: AppConfig.hoverCollapseDelay)

    /// 系统采样间隔（秒）
    static let systemSampleInterval = Key<Double>("systemSampleInterval", default: 1.5)

    /// 无媒体时收起态轮播切换间隔（秒）
    static let collapsedRotateInterval = Key<Double>("collapsedRotateInterval", default: 3.0)

    /// 是否已完成首次引导
    static let hasCompletedOnboarding = Key<Bool>("hasCompletedOnboarding", default: false)

    /// 非刘海屏是否显示虚拟灵动岛
    static let showVirtualNotch = Key<Bool>("showVirtualNotch", default: true)

    /// 默认播放器 bundle id（无媒体播放时点击播放打开的应用）
    static let defaultPlayer = Key<String?>("defaultPlayer", default: DefaultPlayerOption.appleMusic.rawValue)

    /// 界面语言（zh-Hans / en）；首次安装跟系统首选语言
    static let language = Key<String>("language", default: AppLanguage.systemDefault.rawValue)
}

/// 设置访问器：读取当前生效的显示顺序
enum AppSettings {
    /// 系统监控显示顺序（注意：不做缺失补全——补全会让"隐藏"设置失效）
    static var systemMetricsOrder: [SystemMetric] {
        Defaults[.systemMetricsOrder].compactMap(SystemMetric.init)
    }
}


/// 默认播放器选项（预列常见国内外播放器）
enum DefaultPlayerOption: String, CaseIterable, Identifiable {
    case appleMusic = "com.apple.Music"
    case spotify = "com.spotify.client"
    case netease = "com.netease.163music"
    case qqMusic = "com.tencent.QQMusicMac"
    case kugou = "com.kugou.mac"
    case kuwo = "com.kuwo.mac"
    case migu = "com.migu.music"
    case amazonMusic = "com.amazon.music"
    case tidal = "com.tidal.desktop"
    case deezer = "com.deezer.desktop"
    case youtubeMusic = "web-youtube-music"

    var id: String { rawValue }

    /// 显示名称
    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .netease: return "网易云音乐"
        case .qqMusic: return "QQ音乐"
        case .kugou: return "酷狗音乐"
        case .kuwo: return "酷我音乐"
        case .migu: return "咪咕音乐"
        case .amazonMusic: return "Amazon Music"
        case .tidal: return "Tidal"
        case .deezer: return "Deezer"
        case .youtubeMusic: return "YouTube Music"
        }
    }
}
