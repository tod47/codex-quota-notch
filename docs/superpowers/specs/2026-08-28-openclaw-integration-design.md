# OpenClaw 微信额度推送设计

## 目标

让 Codex Quota Notch 在本机读取到周额度与 Plus 5 小时额度后，按有意义的状态变化把摘要发送到本机 OpenClaw Gateway，再由已配置的 `openclaw-weixin` 通道投递到用户微信。

## 范围

- 支持 OpenClaw Gateway 的本机 HTTP Hook，默认地址为 `http://127.0.0.1:18789/hooks/agent`。
- 支持在应用设置中开启/关闭推送，配置 Gateway 地址、通道、微信 Target 和可选 Account ID。
- Hook Token 使用 macOS Keychain 保存，不进入 `UserDefaults`、Git 或日志。
- 推送包含周额度、5 小时额度、各自重置时间/倒计时和今日 token；缺失的额度显示为 `—`，不猜测数据。
- 首次获得有效额度时推送一次状态；周额度或 5 小时额度的剩余百分比/重置周期变化时推送；现有周额度提醒、重置和用尽事件通过同一通道推送。
- 5 小时额度的新重置周期发送明确的“5 小时额度已重置”消息。
- 相同状态不会重复发送；网络失败会在当前进程内保留待发送事件并在下一次刷新重试。
- 应用继续保持本地读取和现有 UI 行为；关闭 OpenClaw 推送不影响额度读取、顶部浮窗或 macOS 通知。

## 不在范围内

- 不实现微信登录、微信协议或新的微信插件。
- 不把 Gateway 暴露到公网。
- 不把 prompt、回复、工具调用、API key 或原始 JSONL 上传给 OpenClaw；只发送格式化额度摘要。
- 不为倒计时每秒发送消息；只在状态变化和既有提醒阈值触发时发送。

## 架构

```text
Codex session JSONL
        ↓
LocalSessionLogDataSource / QuotaMonitor
        ↓
AppModel
        ├─ existing overlay + macOS notification sinks
        └─ OpenClawPushPlanner → OpenClawHookClient
                                      ↓ HTTP loopback + Bearer token
                              OpenClaw Gateway /hooks/agent
                                      ↓
                               openclaw-weixin → WeChat
```

`OpenClawPushPlanner` 是纯值类型逻辑，使用上一份快照、当前快照和持久化投递状态生成去重后的事件。`OpenClawHookClient` 只负责验证配置、编码 JSON、发送 HTTP 请求和有限重试。两者分开以便不启动窗口、不访问 Keychain、不访问网络即可测试规则。

## 配置与安全

新增 `OpenClawPushSettings` 并作为 `AppSettings.openClaw` 持久化，默认关闭，默认 Gateway 为 `http://127.0.0.1:18789`，默认通道为 `openclaw-weixin`。Token 由 `SecretStore` 抽象访问，生产实现使用 Keychain service `com.codexquotanotch.openclaw`，测试使用内存实现。

Hook 请求使用：

```json
{
  "name": "codex-quota-notch",
  "message": "格式化后的额度文本",
  "deliver": true,
  "channel": "openclaw-weixin",
  "to": "用户配置的微信 Target",
  "accountId": "用户配置的账号（可选）"
}
```

应用不记录 Token，不把请求体写入日志；失败状态只显示通用错误，不包含认证头和响应敏感内容。

## 失败与重试

- 未配置 Token、通道或 Target 时不发请求，设置页显示“未配置”。
- URL 非 `http`/`https` 或没有主机名时不发请求。
- HTTP 2xx 视为成功；其他状态视为失败，最多尝试 3 次，采用短指数退避。
- 同一事件最多同时存在一个发送任务；失败事件留在内存中，下一次额度快照到来时再次尝试。
- OpenClaw 不运行或微信通道离线只影响推送，应用继续显示本地额度。

## 设置界面

在主窗口导航中新增“OpenClaw / 微信推送”页面，包含：

- 启用推送
- Gateway 地址
- 通道（默认 `openclaw-weixin`）
- 微信接收 Target
- 可选 Account ID
- SecureField Token、保存/清除 Token
- 状态变化推送开关
- 额度提醒推送开关
- 测试推送按钮和最近一次投递状态

页面同时提供中文和英文文案，并明确说明 Token 只保存在本机 Keychain。

## 验收标准

1. `swift test` 全部通过，并包含配置迁移、Token 存取、事件去重、5 小时重置、双额度消息格式、HTTP 请求和失败重试测试。
2. OpenClaw 推送关闭时不会创建网络请求；开启但缺配置时不会创建网络请求。
3. 相同快照不会重复发送；周额度提醒与 5 小时重置会在对应事件发生时发送一次。
4. Hook 请求包含专用 Bearer Token、显式 `channel`、显式 `to`，并且不包含原始 session 内容。
5. macOS 13 Ventura 及以上构建成功，应用设置可以保存并在重启后恢复。
6. 测试推送可以从设置页触发；桌面版应用启动后设置页能看到完整配置项。
