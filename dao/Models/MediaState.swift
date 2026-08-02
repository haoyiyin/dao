import Foundation

/// 媒体播放状态（视图层数据模型，由 MediaManager 统一发布）
struct MediaState: Equatable {
    /// 标题
    var title: String?
    /// 艺术家
    var artist: String?
    /// 专辑
    var album: String?
    /// 总时长（秒）
    var duration: TimeInterval?
    /// 已播放时间（秒，最近一次更新的快照值）
    var elapsedTime: TimeInterval?
    /// 快照时间戳（秒，epoch；配合 elapsedTime 做本地插值）
    var timestamp: TimeInterval?
    /// 播放速率（0 = 暂停）
    var playbackRate: Double = 1
    /// 封面数据（JPEG/PNG，由 artworkData base64 解码）
    var artworkData: Data?
    /// 播放应用 bundle identifier
    var bundleIdentifier: String?
    /// 是否为音乐类应用（白名单 / 流字段；UI 与优先策略参考）
    var isMusicApp: Bool = false
    /// 播放中标记（透传流字段；部分应用缺失时用 playbackRate 兜底）
    var playingFlag: Bool?
    /// 播放中标记：优先流字段，其次 playbackRate > 0
    var isPlaying: Bool {
        if let playingFlag { return playingFlag }
        return playbackRate > 0
    }
    /// 是否存在活跃媒体会话（无播放时 false）
    var isActive: Bool = false
    /// 随机播放模式（透传 MediaRemote 模式值，UI 层映射）
    var shuffleMode: Int?
    /// 循环模式（透传 MediaRemote 模式值，UI 层映射）
    var repeatMode: Int?

    /// 空状态（无活跃媒体会话）。注意：必须用无参 init 构造，
    /// 否则 init(update:) 内 `self = .empty` 会触发 dispatch_once 重入崩溃
    static let empty = MediaState()

    /// 默认初始化（全部字段为空）
    init() {}

    /// 由 MediaRemoteAdapter 流更新构造（纯函数，便于单元测试）
    init(update: MediaRemoteUpdate?) {
        guard let update else {
            self = .empty
            return
        }
        title = update.title
        artist = update.artist
        album = update.album
        duration = update.duration
        elapsedTime = update.elapsedTime
        timestamp = update.timestamp.flatMap(MediaState.parseISO8601)
        playbackRate = update.playbackRate ?? 1
        playingFlag = update.playing
        artworkData = update.artworkData.flatMap { Data(base64Encoded: $0) }
        // 部分应用只上报 parentApplicationBundleIdentifier
        let resolvedBundle = update.bundleIdentifier ?? update.parentApplicationBundleIdentifier
        bundleIdentifier = resolvedBundle
        isMusicApp = update.isMusicApp ?? Self.isKnownMusicApp(resolvedBundle ?? "")
        shuffleMode = update.shuffleMode
        repeatMode = update.repeatMode
        isActive = true
    }
    /// 解析 ISO8601 时间戳（含/不含小数秒）→ epoch 秒；失败返回 nil
    static func parseISO8601(_ string: String) -> TimeInterval? {
        if let date = isoFormatter.date(from: string) {
            return date.timeIntervalSince1970
        }
        // 兼容小数秒（ISO8601 默认格式不含小数秒）
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        defer { isoFormatter.formatOptions = [.withInternetDateTime] }
        return isoFormatter.date(from: string)?.timeIntervalSince1970
    }

    /// 是否为已知音乐应用（视频/浏览器等非音乐应用返回 false）
    nonisolated static func isKnownMusicApp(_ bundleID: String) -> Bool {
        switch bundleID {
        case "com.apple.Music", "com.spotify.client",
             "com.netease.163music", "com.tencent.QQMusicMac", "com.kugou.mac",
             "com.kuwo.mac", "com.migu.music", "com.amazon.music",
             "com.tidal.desktop", "com.deezer.desktop":
            return true
        default:
            return false
        }
    }

    /// 是否为浏览器（含 helper / 前缀族）。网页 MediaRemote 会话识别用。
    nonisolated static func isBrowserApp(_ bundleID: String?) -> Bool {
        guard let id = bundleID, !id.isEmpty else { return false }
        // 前缀：Chrome / Edge / Brave / Firefox / Safari 族（含 helper、PWA）
        if id.hasPrefix("com.google.Chrome")
            || id.hasPrefix("com.brave.Browser")
            || id.hasPrefix("com.microsoft.edgemac")
            || id.hasPrefix("org.mozilla.firefox")
            || id.hasPrefix("com.apple.Safari") {
            return true
        }
        switch id {
        case "company.thebrowser.Browser", // Arc
             "com.operasoftware.Opera",
             "com.vivaldi.Vivaldi",
             "com.sigmaos.sigmaos.macos",
             "com.kagi.kagimacOS":
            return true
        default:
            return false
        }
    }

    /// 浏览器垫底：非浏览器流更新始终采纳；垫底锁定时忽略浏览器流。
    /// - Returns: `(apply, clearDemotion)`
    nonisolated static func browserDemotionDecision(
        newState: MediaState,
        browserDemoted: Bool
    ) -> (apply: Bool, clearDemotion: Bool) {
        if !isBrowserApp(newState.bundleIdentifier) {
            return (true, true)
        }
        if browserDemoted {
            return (false, false)
        }
        return (true, false)
    }

    /// ISO8601 解析器（缓存复用）
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// MediaRemoteAdapter 流 JSON 原始模型（字段与 adapter keys.m 一一对应）
struct MediaRemoteUpdate: Decodable, Equatable {
    let title: String?
    let artist: String?
    let album: String?
    /// 总时长（秒）
    let duration: Double?
    /// 已播放时间（秒）
    let elapsedTime: Double?
    /// 快照时间戳（ISO8601 字符串，如 "2026-08-01T09:44:22Z"；部分应用可能上报数字）
    let timestamp: String?
    /// 播放中标记（部分应用缺失，用 playbackRate 兜底）
    let playing: Bool?
    /// 播放速率
    let playbackRate: Double?
    /// 应用 bundle id
    let bundleIdentifier: String?
    /// 父应用 bundle id（如网页播放器的宿主浏览器）
    let parentApplicationBundleIdentifier: String?
    /// 封面 MIME 类型
    let artworkMimeType: String?
    /// 封面数据（base64）
    let artworkData: String?
    let shuffleMode: Int?
    let repeatMode: Int?
    let isMusicApp: Bool?
}
