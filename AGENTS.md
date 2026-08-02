# AGENTS.md

> Native macOS 灵动岛（Dynamic Island）app：SwiftUI + AppKit `NSPanel` 悬浮窗，媒体控制 / 文件暂存架 / 系统监控。XcodeGen 工程。

## Architecture

In `dao/` where app source lives:

| Path | Role |
|------|------|
| `dao/App/` | `@main` entry (`DaoApp`), `AppDelegate`, `AppCoordinator` (MVVM-C 的 C) |
| `dao/Config/` | `AppConfig` — 全部窗口尺寸 / 延迟 / 层级常量 |
| `dao/Managers/` | 全局单例 Manager（`.shared`），`@MainActor` |
| `dao/Models/` | 状态模型 + `AppSettings`（Defaults keys）+ `LanguageManager` |
| `dao/Monitors/` | Battery / CPU / Disk / Memory / Network 采样 |
| `dao/Views/` | Notch 窗体、收展态、媒体/架/设置 UI |
| `dao/Resources/` | 打包资源（含 `mediaremote-adapter.pl`） |
| `dao/Utils/` | 屏幕刘海检测、扩展 |
| `daoTests/` | XCTest，`@testable import dao` |
| `Vendor/` | MediaRemote 适配器源码 + 构建产物（framework 不提交） |
| `Scripts/` | 适配器构建脚本 |
| `project.yml` | **XcodeGen 源真相**（勿手改 `dao.xcodeproj`） |

### Rules

1. **Edit `project.yml` then regenerate**. Never hand-edit `project.pbxproj`.
   ```bash
   xcodegen generate
   ```
   New Swift files under existing `dao/` groups are picked up automatically. New targets / packages / Info.plist keys → edit `project.yml`.

2. **MVVM-C wiring stays in `AppCoordinator`**. Managers are singletons; Views bind `@Published`. Do not spawn parallel coordinators or put startup order in Views.

3. **Media control path is fixed**:
   - Primary: `MediaRemoteStreamAdapter` (perl + `MediaRemoteAdapter.framework`)
   - Fallback: `AppleScriptController`
   - Router: `MediaCommandRouter` over protocol `MediaControlling`
   - Do **not** call MediaRemote private APIs directly from the app binary (macOS 15.4+ blocks this; perl path is intentional and verified).

4. **Magic numbers live in `AppConfig` only**. Window geometry, hover delays, window level (`.mainMenu + 3`) — add constants there; update `SmokeTests` when geometry contracts change.

5. **Fixed window strategy (Strategy A)**: window frame is always expanded geometry (`400×166`). Collapse/expand is visual (`NotchShape` + mask), not `NSWindow` resize.
   - Content that should clip with the capsule: put under `.mask(NotchShape)` driven by the same `visualSize` animation.
   - Toast / chrome that must not ghost: keep **outside** the mask.
   - Residual wing ghosting after mask: prefer asymmetric fade / tighten `mediaActive` collapse — do not "fix" by resizing the window.

6. **`@MainActor` on managers / window controllers**. Background work (monitor sampling, stream IO) stays off main; publish state back on main.

7. **Settings via `Defaults` keys in `AppSettings`**. No raw `UserDefaults` string keys scattered in Views.

8. **Comments / docs: Simplified Chinese. Identifiers: English.**

### Anti-patterns

```swift
// WRONG: hand-edit pbxproj or add target only in Xcode UI without project.yml
// CORRECT: project.yml → xcodegen generate

// WRONG: call MediaRemote from app process
// CORRECT: MediaRemoteStreamAdapter → perl → framework; AppleScript fallback

// WRONG: resize NSWindow for collapse/expand
// CORRECT: fixed expanded frame; animate NotchShape + mask visualSize

// WRONG: magic numbers in Views
// CORRECT: AppConfig.expandedWidth / hoverExpandDelay / …

// WRONG: commit Vendor/MediaRemoteAdapter.framework or build-mediaremote-adapter/
// CORRECT: gitignore binaries; rebuild via Scripts/build-mediaremote-adapter.sh
```

## Build / Run / Test

Requirements: Xcode (macOS 14+ SDK), Homebrew tools:

```bash
brew install xcodegen swiftlint cmake
```

```bash
# Regenerate Xcode project after project.yml / source layout changes
xcodegen generate

# Build
xcodebuild -project dao.xcodeproj -scheme dao -destination 'platform=macOS' build

# Test
xcodebuild test -project dao.xcodeproj -scheme dao -destination 'platform=macOS'

# Lint (non-blocking in Xcode pre-build: swiftlint || true)
swiftlint

# Adapter framework only
Scripts/build-mediaremote-adapter.sh
# missing cmake → warning + AppleScript fallback at runtime (exit 0)
```

Debug: open `dao.xcodeproj`, scheme `dao`. App is `LSUIElement` (no Dock icon) — look for notch panel / Activity Monitor.

Release (fill placeholders in `build.sh` first):

```bash
./build.sh [version]   # archive → licenses → sign → DMG → notary → stapler → appcast sign
```

Sparkle fields in `project.yml` (`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`) are placeholders until ship config is real.

## Media remote adapter

- Source: `Vendor/mediaremote-adapter` (ungive/mediaremote-adapter, MIT, vendored — not a submodule).
- Output: `Vendor/MediaRemoteAdapter.framework` (gitignored); pre-build script always rebuilds when cmake present.
- Bundled script: `dao/Resources/mediaremote-adapter.pl` **must stay in sync** with `Vendor/mediaremote-adapter/bin` counterpart.
- Stream protocol: JSON lines; `diff=false` full snapshot, `diff=true` partial (NSNull clears fields). Merge logic in `StreamPayloadAccumulator` (unit-tested).

## Testing

- Framework: XCTest only (`@testable import dao`).
- Prefer pure structs for logic (`StreamPayloadAccumulator`) and injectable paths (`ShelfManager.baseURL`) so tests avoid UI/process.
- Geometry / product invariants: `daoTests/SmokeTests.swift` — keep green when touching `AppConfig` or `ScreenNotchDetector`.
- No CI in repo yet; local `xcodebuild test` is the gate.

## Style

From `.swiftlint.yml`:

- Line length warn 140 / error 200
- Opt-in: `empty_count`, `closure_end_indentation`, `sorted_first_last`
- Disabled: trailing/vertical whitespace
- Lint failure does **not** fail build — still fix new violations you introduce

## Security / privacy notes

- `NSAppleEventsUsageDescription` required for media AppleScript fallback.
- Shelf uses security-scoped bookmarks — preserve bookmark restore path in `ShelfManager`.
- Hardened Runtime on (`ENABLE_HARDENED_RUNTIME: YES`).
- Never commit signing secrets, notary passwords, or filled Developer ID lines from a local `build.sh` edit.

## Code review checklist

- [ ] `project.yml` updated if targets/packages/plist/scripts changed; ran `xcodegen generate`
- [ ] No framework/build binaries under `Vendor/` staged
- [ ] Media path still primary→fallback via `MediaControlling`
- [ ] Window still fixed expanded size; visual collapse uses mask, not window resize
- [ ] New constants in `AppConfig`; SmokeTests adjusted if geometry contracts moved
- [ ] Settings keys only via `AppSettings` / Defaults
- [ ] Main-actor boundaries respected for UI state
- [ ] `mediaremote-adapter.pl` still synced if adapter script changed
- [ ] Release path: licenses still copied in `build.sh` for new deps

## Do not

- Add npm/JS tooling or rewrite as Catalyst/iOS
- Replace perl MediaRemote bridge with in-process private API calls
- Introduce a second settings store beside Defaults
- Commit `DerivedData/`, `.swiftpm/`, or adapter build products
