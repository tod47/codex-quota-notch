# Codex Quota Notch

Codex Quota Notch 是一个原生 macOS 菜单栏应用，用于在本机显示 Codex 的七天周额度、下次重置时间和当天 token 使用量。鼠标指针移动到当前屏幕顶部中心（有刘海时就是刘海区域）会显示默认的方形圆角浮窗；没有刘海的屏幕和外接显示器也使用顶部中心位置。

The app is built with SwiftUI and AppKit for macOS 13 Ventura and newer. It reads local Codex desktop-app and CLI session logs, shows the remaining weekly quota in the menu bar, and supports a hover popup, a persistent top panel, and a draggable/resizable floating panel. Clicking the app from Finder, reopening it, or left-clicking the menu bar quota opens the settings window; right-clicking the menu bar quota keeps the refresh and quit shortcuts.

## Features / 功能

- 读取本机 Codex session JSONL，默认路径为 `~/.codex/sessions`。
- 选择 `window_minutes = 10080` 的限额作为七天周额度，并将 Plus 的 `window_minutes = 300` 限额作为 5 小时额度，不把其他短时限额误标成这两种额度。
- 菜单栏实时显示剩余百分比，并按额度状态显示绿色、琥珀色或红色。
- 顶部中心悬停弹窗同时显示周额度和 5 小时额度（各自的剩余百分比、重置日期与倒计时），以及今日 token 和数据状态；没有 5 小时数据时自动隐藏该区块。
- 弹窗底部提供刷新按钮；当数据已过期或暂时不可用时，可以立即强制重新扫描本机 Codex session，并显示刷新状态。
- 可在“外观与展示”设置中独立开启或关闭 5 小时额度显示，默认开启；关闭只影响显示，不影响本地数据读取。
- 剩余 90%、80%……20% 时按 10% 步进提醒；剩余 10% 至 1% 时逐 1% 提醒；用尽时单独提醒。
- 在距离重置 2 天、1 天和 5 小时时提醒；检测到新周期后提示已重置。
- 顶部浮窗和 macOS 系统通知可以分别开关。
- 自动跟随系统深浅色，也可在主窗口固定浅色或深色。
- 顶部弹窗、顶部常驻、自由浮窗三种展示模式；自由浮窗支持拖动、缩放和记忆位置。
- 默认登录启动，主窗口提供数据路径、提醒、外观和隐私设置。
- 中文 / English 可在设置中自由选择，也可以跟随 macOS 系统语言。

## Privacy / 隐私

默认情况下所有数据都只在本机读取。应用只提取时间戳、额度字段和 token 统计，不上传 prompt、回复内容、工具调用、API key 或原始 session 内容，也不会修改 Codex 的会话文件。

如果你在设置中主动启用 OpenClaw 推送，应用只会把格式化后的周额度、5 小时额度、重置时间/倒计时和今日 token 摘要发送给你配置的 OpenClaw Gateway；原始 session 内容仍不会离开本机。Hook Token 只保存在 macOS Keychain 中，不会写入设置文件、Git 或日志。

Codex 的本地 session 格式属于实现细节，未来格式变化可能导致部分字段暂时不可用；应用会显示“数据不可用”或“周额度不可用”，不会猜测额度。

弹窗中的“刷新”会强制重新扫描本机 session 文件并清除增量缓存。如果 Codex 尚未把新的 `rate_limits` 写入本地 session，刷新后仍会保留上一次真实记录并继续标记为过期，不会猜测新的重置时间。

## OpenClaw / 微信推送

应用通过 OpenClaw Gateway 的本机 Hook 接口发送通知，再由你已经配置好的微信通道投递到手机。它不实现微信登录或微信协议，也不会直接连接微信。默认推送关闭，只有在“OpenClaw / 微信推送”设置页填写并保存配置后才会发送。

推荐的数据流是：

```text
Codex Quota Notch → http://127.0.0.1:18789/hooks/agent → OpenClaw → openclaw-weixin → 微信
```

在 OpenClaw Gateway 中启用 Hooks（示例只使用占位符；请把 Token 保存在本机安全位置）：

```json5
{
  hooks: {
    enabled: true,
    token: "<dedicated-hook-token>",
    path: "/hooks",
    allowedAgentIds: ["main"],
    allowRequestSessionKey: false
  }
}
```

然后在本应用设置页填写：

- Gateway 地址：默认 `http://127.0.0.1:18789`；如果你的 Gateway 运行在其他受信任的本机或内网地址，可以改成对应的 `http`/`https` 地址。
- OpenClaw 通道：微信插件通常填写 `openclaw-weixin`。
- 微信接收 Target：填写 OpenClaw 微信通道要求的接收目标；应用不会猜测或自动发送给未知联系人。
- Account ID：只有配置了多个微信账号时才需要填写，否则留空。
- Hook Token：填写上面配置的专用 Hook Token，点击“保存 Token”。它会进入本机 Keychain，不会进入 `UserDefaults`。

“推送额度状态变化”会在首次获得有效状态、百分比或重置周期变化时发送一条包含周额度和 5 小时额度的摘要；“推送额度提醒”会转发周额度的百分比、倒计时、重置和用尽提醒。相同状态不会重复推送，网络失败会在下一次额度更新时重试。5 小时周期变化会单独推送“5 小时额度已重置”。

测试时可以先用占位符替换为你自己的值，在本机验证 Hook：

```bash
curl -X POST http://127.0.0.1:18789/hooks/agent \
  -H 'Authorization: Bearer <dedicated-hook-token>' \
  -H 'Content-Type: application/json' \
  --data '{
    "name": "codex-quota-notch",
    "message": "Codex quota test",
    "deliver": true,
    "channel": "openclaw-weixin",
    "to": "<wechat-target>"
  }'
```

请保持 Gateway 只监听回环地址或受信任的内网，不要把 `/hooks` 直接暴露到公网；Hook Token 仅用于这个专用接口。当前应用不会在仓库中保存任何实际 Token、微信 Target 或账号信息。

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
├── OpenClaw/     安全配置、事件去重和 Gateway Hook 推送
├── Settings/     设置和提醒状态持久化
└── UI/           SwiftUI 视图与 AppKit 窗口控制器
```

测试 fixture 只使用脱敏的合成数据。请不要把自己的 `.codex`、日志、API key 或真实会话内容提交到仓库。

## License / 许可证

MIT License。详见 [`LICENSE`](LICENSE)。
