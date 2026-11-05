# FluxKit 迭代状态（P0 / P1 / 待办）

> 定位：HLS / 直链 / 播客 / 自有媒体下载器。
> 本文件记录 P0 / P1 / P2 的完成情况，以及仍需人工或商店后台完成的事项。

## P0 — 已完成

| 项目 | 状态 | 实现要点 |
|---|---|---|
| 后台音频播放 | ✅ | `AVAudioSession(.playback)` + `UIBackgroundModes: audio`；锁屏/后台继续播放 |
| 锁屏 & 耳机控制 | ✅ | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`（播放/暂停/拖动进度） |
| HLS 暂停 / 继续 | ✅ | 暂停取消任务、保留已下载分片；继续复用分片 |
| HLS 崩溃/重启续传 | ✅ | 每个分片落盘（`AppPaths.hlsWork`）；启动时把中断任务标记为「已暂停」 |
| HLS 大小估算修复 | ✅ | 支持 `EXT-X-BYTERANGE`（含 `EXT-X-MAP` 的 BYTERANGE），不再按整文件估算 |
| 直播流识别 | ✅ | 无 `EXT-X-ENDLIST` 且非 VOD → 明确提示「暂不支持直播流」 |
| Referer 透传 | ✅ | 从网页解析出的媒体带上页面 `Referer`；播客带上 feed URL |
| 下载队列 / 并发上限 | ✅ | 1–4 并发，其余排队；完成/失败/暂停自动出队 |
| 仅 Wi-Fi | ✅ | `NWPathMonitor` 监听网络；蜂窝网络下任务停在队列并提示 |
| 设置页 | ✅ | 下载、播客、通知、存储、语言、关于 |
| 失败/完成通知 | ✅ | 本地通知，默认关闭，开启时请求权限 |
| 真机签名 / Archive | ✅ | Team `H5YQ9HSATA`；Debug、Release Archive、App Store 导出均验证通过 |

## P1 — 已完成

| 项目 | 状态 | 说明 |
|---|---|---|
| 播客订阅 | ✅ | 新「播客」Tab；订阅/取消订阅、最新一期、刷新 |
| 播客自动下载 | ✅ | 设置里选 Off/1/3/5，刷新或订阅时自动下载最新 N 期（去重） |
| OPML 导入导出 | ✅ | 设置页导出（分享 OPML）/ 导入（fileImporter） |
| 播客封面持久化 | ✅ | 下载完成时保存远端封面，片库/任务列表可显示 |
| 播放器增强 | ✅ | 倍速、续播、后台音频、锁屏控制、播放队列/上一集/下一集、**字幕（内嵌 + HLS WebVTT）**、**画中画** |
| 已听进度 | ✅ | 片库显示进度条 / Resume / Played；播客列表也显示状态；`lastPosition` + `played` 持久化 |
| 片库管理 | ✅ | 搜索、排序、多选删除、存储统计 |
| 播放进度记忆 | ✅ | 每 5 秒与退出时写入；接近结尾时自动清除 |
| 音频界面 | ✅ | 无视频轨时显示「正在播放」卡片；音频隐藏「存相册」 |
| 下载失败文案 | ✅ | 统一友好提示，技术细节只在 DEBUG 日志 |
| 空状态/提示精简 | ✅ | 首页只保留一行提示 + 免责声明 |
| 通知权限 | ✅ | 设置内开关，按需请求 |

## 追加完成（本轮 P2）

| 项目 | 状态 | 说明 |
|---|---|---|
| 字幕轨 | ✅ | 内嵌字幕/音轨选择（AVMediaSelectionGroup）+ HLS 字幕 rendition 下载为 WebVTT + 覆盖层渲染；`WebVTTParser` 有单测 |
| 画中画 | ✅ | `AVPictureInPictureController` + 隐藏 `AVPlayerLayer` 源；锁屏/后台继续播放 |
| CI 流水线 | ✅ | `.github/workflows/ci.yml`：生成工程 → 起模拟器 → 单元测试 → UI 测试 → Release 编译 |
| Pro 订阅 | ✅ | **StoreKit 2 + RevenueCat 5.102**：offerings、购买、恢复、entitlement `pro` 实时同步；并发与播客自动下载门控；详见 `docs/PRO.md` |
| Files App | ✅ | 媒体迁移到 Documents/FluxKit/Media（Files 可见、名称友好、排除 iCloud 备份）+ 从文件导入 |
| 播放队列 / 已听进度 | ✅ | 上一集/下一集、自动连播；进度条 / Resume / Played 持久化 |
| UI 测试 | ✅ | 6 条 XCUITest：首页、设置、搜索、多选、Paywall、Pro 状态 |

## 仍需人工完成（非代码）

| 项目 | 说明 |
|---|---|
| Pro 商品创建 | 在 App Store Connect 建订阅组与两个商品，价格/审核截图；代码里的 ID 已固定 |
| StoreKit 本地配置 | Xcode 新建 `.storekit` 并挂到 Scheme，步骤见 `docs/PRO.md` |
| CI 仓库账号 | 推送后把 README 徽章里的 `OWNER` 换成真实 GitHub 仓库 |
| 广告 SDK / ATT / UMP | `SponsorSlot` 已预埋，默认关闭；接入需 SDK 与合规配置 |
| 商店物料 | 6.9" 营销截图、隐私/支持页托管（`fastlane/metadata` 文案已就绪） |
| Files 导入 UI 回归 | 已支持 fileImporter 与 Documents 可见；可补一条系统文件选择器的 UI 测试 |
| 小组件 / 快捷指令 | 增长功能，优先级低于稳定性 |

## 已知限制（产品文案已体现）

- HLS 下载在 App 被系统挂起时会暂停，回到前台继续；直链下载可在后台完成。
- 直播流、DRM、平台受限链接（抖音/TikTok/YouTube 等）不支持，会给出明确原因。
- 播客订阅缓存最近 100 期，避免订阅文件无限增长。
