# FluxKit 产品定位（HLS / 直链 / 播客 / 自有媒体）

## 一句话

> 把 **HLS 播放列表、音视频直链、播客节目** 保存到 iPhone，离线也能看、能听。

英文：**Save HLS playlists, direct links, and podcast episodes for offline playback — on your iPhone, no account.**

## 目标用户

| 用户 | 场景 |
|---|---|
| 播客听众 | 通勤/飞机上想听已订阅的节目，不想依赖在线流 |
| 课程/会议用户 | 主办方给了 HLS 或 MP4 回放链接，想存到本地 |
| 创作者 | 下载自己上传到 CDN / S3 / 对象存储的成片做备份 |
| 自建媒体用户 | NAS、Cloudflare Stream、自托管 HLS 的离线观看 |
| 网络不稳定地区 | 先下好再看不卡顿 |

## 支持 / 不支持（产品边界）

**支持**

- HLS / `.m3u8`（含 master playlist、独立音轨、AES-128 分片）
- 直链：MP4 / MOV / M4V / WebM / MP3 / M4A / AAC / WAV / OGG
- 播客 RSS / Atom 订阅（选节目、按最新排序、显示时长与大小）
- 公开网页里通过 `og:video`、`<video>`、`<source>`、JSON-LD 暴露的媒体
- 分享扩展、`fluxkit://` 深链、后台下载、断点续传、离线播放

**不支持（明确拒绝并说明原因）**

- DRM、付费墙、需要登录的内容
- 只在平台 App 内播放的受限链接（临时签名地址）：抖音、TikTok、YouTube、Instagram、
  Facebook、X、快手、小红书、B 站、Netflix 等
- 去水印、批量抓取、绕过地区限制

## 为什么这条路线更合规

1. **不触碰 App Review 5.2.3 的核心雷区**：不做「从第三方平台保存/转换/下载媒体」，
   只处理用户提供的直链、HLS、RSS 和公开网页里的媒体。
2. **不涉及反规避（DMCA §1201 / 欧盟 DSM）**：不破解 DRM、不伪造签名、不绕登录。
3. **不依赖平台接口**：平台改版不会让你的产品失效；没有「今天能用明天不能用」的问题。
4. **定位清晰，审核备注好写**：用途是离线保存自有/授权媒体，而不是「全网视频下载」。
5. **可持续经营**：可以做订阅（Pro 解锁并发数、批量播客、iCloud 备份等），而不是靠灰色流量。

> 仍然要保留「只下载你有权保存的媒体」提示，并在审核备注中说明不处理平台受限链接。

## ASO 策略

- 标题：`FluxKit: HLS & Podcast Saver`（30 字符）
- 副标题：`Save HLS, links & podcasts.`（27）
- 关键词（96）：`hls downloader,m3u8,mp4,mp3,podcast downloader,offline media,media saver,direct link,audio,video`
- 避免在名称/关键词里写 YouTube / TikTok / 抖音 等平台名（商标 + 误导性元数据风险）
- 截图顺序建议：首页（输入框+说明）→ 播客节目列表 → 下载/后台任务 → 离线播放 → 隐私
- 文案强调：离线、后台、断点续传、无账号、本地处理；弱化「破解/去水印」

## 商店文案

已写入 `fastlane/metadata/`：

- `en-US`：名称、副标题、关键词、推广文本、描述、更新日志
- `zh-Hans`：同上

链接与版权方已指向 `openkit.cloud`；版权方 `OpenKit`，支持邮箱 `support@openkit.cloud`。

## 审核备注（要点）

- 用途：保存用户有权保留的 HLS/直链/播客节目，供离线播放。
- 不解析平台受限链接，不绕过 DRM/登录/付费；遇到这类链接会提示原因。
- 无账号、无分析 SDK、无云端；下载直连源站。
- 播客订阅只读取公开 RSS/Atom 的 enclosure 地址。
- 测试方式：粘贴任意公开 HLS/MP4 直链，或粘贴 `https://feeds.npr.org/510289/podcast.xml` 体验播客列表。

完整英文模板见 `docs/STORE_REVIEW_NOTES.md`。

## 已具备 / 下一步

已完成：播客订阅（含 OPML 导入导出、自动下载）、下载队列与并发、仅 Wi-Fi、
HLS 断点续传、后台音频与锁屏控制、倍速与续播、片库搜索/排序/批量删除、
本地完成通知。详见 [`ROADMAP.md`](ROADMAP.md)。

下一步建议：

1. S3 / Cloudflare Stream / 自建服务器的快捷预设（粘贴域名即可）
2. 播放队列 / 下一集、字幕与画中画
3. iCloud / 文件 App 备份与导入
4. 订阅制（Pro），而不是广告：与「离线工具」定位更匹配
