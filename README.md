# Codex Quota Notch

Codex Quota Notch 是一个原生 macOS 菜单栏应用，用于在本机显示 Codex 的七天周额度、下次重置时间和当天 token 使用量。鼠标指针移动到当前屏幕顶部中心（有刘海时就是刘海区域）会显示默认的方形圆角浮窗；没有刘海的屏幕和外接显示器也使用顶部中心位置。

The app is built with SwiftUI and AppKit for macOS 13 Ventura and newer. It reads local Codex desktop-app and CLI session logs, shows the remaining weekly quota in the menu bar, and supports a hover popup, a persistent top panel, and a draggable/resizable floating panel.

## Features / 功能

- 读取本机 Codex session JSONL，默认路径为 `~/.codex/sessions`。
- 选择 `window_minutes = 10080` 的限额作为七天周额度，不把短时限额误标成周额度。
- 菜单栏实时显示剩余百分比，并按额度状态显示绿色、琥珀色或红色。
- 顶部中心悬停弹窗显示周额度、重置日期、倒计时、今日 token 和数据状态。
- 剩余 90%、80%……20% 时按 10% 步进提醒；剩余 10% 至 1% 时逐 1% 提醒；用尽时单独提醒。
- 在距离重置 2 天、1 天和 5 小时时提醒；检测到新周期后提示已重置。
- 顶部浮窗和 macOS 系统通知可以分别开关。
- 自动跟随系统深浅色，也可在主窗口固定浅色或深色。
- 顶部弹窗、顶部常驻、自由浮窗三种展示模式；自由浮窗支持拖动、缩放和记忆位置。
- 默认登录启动，主窗口提供数据路径、提醒、外观和隐私设置。
- 中文 / English 根据 macOS 系统语言切换。

## Privacy / 隐私

所有数据都在本机读取。应用只提取时间戳、额度字段和 token 统计，不上传 prompt、回复内容、工具调用、API key 或原始 session 内容，也不会修改 Codex 的会话文件。

Codex 的本地 session 格式属于实现细节，未来格式变化可能导致部分字段暂时不可用；应用会显示“数据不可用”或“周额度不可用”，不会猜测额度。

## Build and run / 构建运行

需要 Xcode 15 或更新版本以及 macOS 13+ SDK。

```bash
swift test
swift build
./scripts/build-app.sh
open build/CodexQuotaNotch.app
```

在 Apple Silicon Mac 上构建当前架构时，`build-app.sh` 会生成 `build/CodexQuotaNotch.app`。如果希望尝试构建 arm64 + x86_64 通用包：

```bash
./scripts/build-app.sh --universal
```

也可以直接运行：

```bash
./scripts/run-app.sh
```

首次运行时，macOS 可能询问通知权限。拒绝通知权限不影响菜单栏、顶部浮窗和主窗口功能。若全局鼠标监听受到系统权限限制，仍可通过菜单栏打开主窗口和刷新数据。

当前仓库提供的是未签名、未公证的直接分发构建。若 Gatekeeper 第一次阻止打开，请在 Finder 中对应用点按右键并选择“打开”，或到“系统设置 → 隐私与安全性”中确认“仍要打开”。

## Data source / 数据来源

默认目录是 `~/.codex/sessions`。如果 Codex 使用了其他本地目录，可以在主窗口的“数据与隐私”中选择目录。应用按 JSONL 行读取 `event_msg` 的 `token_count` 和 `rate_limits` 字段，损坏的行会跳过。

今日 token 和最近七天统计根据本机 session 中的累计 token 快照计算，可能与账户侧最终计费数据存在差异。

## Development / 开发

```text
Sources/CodexQuotaNotch/
├── App/          应用生命周期、状态模型和系统通知
├── Alerts/       额度提醒状态机
├── Data/         JSONL 解析和 token 聚合
├── Models/       额度、快照和提醒模型
├── Monitoring/   本地文件监听与刷新
├── Settings/     设置和提醒状态持久化
└── UI/           SwiftUI 视图与 AppKit 窗口控制器
```

测试 fixture 只使用脱敏的合成数据。请不要把自己的 `.codex`、日志、API key 或真实会话内容提交到仓库。

## License / 许可证

MIT License。详见 [`LICENSE`](LICENSE)。
