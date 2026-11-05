# FluxKit Support

FluxKit is an offline media saver for iPhone. Paste a link (or share one from another app), tap
**Download**, and watch or listen without a network. It saves HLS playlists (`.m3u8`), direct
media links, podcast episodes, and files you import from the Files app.

## Contact

Email **support@openkit.cloud** — we usually reply within 2 business days.
Please include your iPhone model, iOS version, the app version (Settings → About), and the link
type you were trying to download if it is relevant. Never send passwords or account credentials.

## Common questions

**Where are my downloads?**
Files app → **On My iPhone → FluxKit → Media**. Inside FluxKit they also appear in the
**Library** tab, and video can be saved to Photos with **Save to Photos**.

**Which links work?**
Direct files (`.mp4`, `.mov`, `.m4v`, `.webm`, `.mp3`, `.m4a`, `.aac`, `.wav`, `.ogg`), HLS
playlists (`.m3u8`), public pages that embed a video with `og:video`, a `<video>` tag or JSON-LD
`contentUrl`, and podcast RSS/Atom feeds.

**Why do Douyin / TikTok / YouTube / Instagram links fail?**
Those apps never expose a downloadable file on the page you share. The playback URL is created
inside their own app session, signed with a short-lived token, and expires within minutes.
FluxKit runs entirely on your iPhone, has no server, and does not fake those signatures, so it
rejects these links immediately with an explanation instead of downloading an HTML page and
failing later. Links that need a login, a subscription, or DRM playback do not work either.

**Live streams?**
A playlist without an end marker (no `EXT-X-ENDLIST`) is a live stream; FluxKit does not record
live streams and says so up front.

**Downloads in the background?**
Direct-link downloads use a background session and can finish while the app is suspended. HLS
downloads pause when iOS suspends the app and continue from the last finished segment when you
come back — pause, crash, or relaunch all resume rather than restart.

**Wi-Fi only.**
Turn on **Settings → Downloads → Wi-Fi only**. On cellular the tasks wait in the queue with a
note instead of using your data.

**FluxKit Pro isn't active after purchase.**
Open **Settings → Upgrade** (or the paywall) and tap **Restore purchases**. Purchases are handled
by Apple through your Apple ID; make sure the device is signed in with the Apple ID that bought
the subscription.

**Manage or cancel a subscription.**
iOS **Settings → Apple ID → Subscriptions**, or
https://apps.apple.com/account/subscriptions. Deleting the app does not cancel a subscription.
Refunds are handled by Apple.

**What is free and what needs Pro?**
Downloading, HLS support, subtitles, Picture in Picture, and Files access are free, one download
at a time. FluxKit Pro (monthly or yearly, auto-renewing) raises the queue to 4 simultaneous
downloads and enables podcast auto-download.

**Notifications.**
Download and failure notifications are off by default; turn them on in **Settings →
Notifications**. The app asks for permission only when you enable them.

**Privacy in one line.**
No account, no analytics, no ads, no tracking. Links are requested straight from the source
server and never sent to us. See the [Privacy Policy](/privacy-policy).

## 中文支持

FluxKit 是 iPhone 上的离线媒体保存工具：粘贴链接（或从其他 App 分享过来），点「下载」，之后
不联网也能看、能听。支持 HLS 播放列表（`.m3u8`）、音视频直链、播客节目，以及从「文件」App 导入
的媒体。

**联系方式：**邮箱 **support@openkit.cloud**，通常 2 个工作日内回复。请附上机型、iOS 版本、App 版本
（设置 → 关于）和出问题的链接类型。请勿发送账号密码。

**下载的文件在哪里？**
「文件」App → **我的 iPhone → FluxKit → Media**。App 内的「片库」也能看到；视频可用「存相册」保存到
「照片」。

**哪些链接可以下载？**
直链文件（`.mp4`、`.mov`、`.m4v`、`.webm`、`.mp3`、`.m4a`、`.aac`、`.wav`、`.ogg`）、HLS
播放列表（`.m3u8`）、用 `og:video`／`<video>`／JSON-LD `contentUrl` 暴露视频的公开网页，以及播客的
RSS/Atom 订阅地址。

**为什么抖音、TikTok、YouTube、Instagram 的链接下不了？**
这些 App 从不把可下载的文件放在你分享出来的页面上：真正的播放地址是在它们自己的会话里生成的，
每次请求都带短时效签名，几分钟就过期。FluxKit 完全在 iPhone 本地运行，没有服务器，也不会伪造这些
签名，所以它会立刻拒绝这类链接并说明原因，而不是先下个网页再失败。需要登录、付费或 DRM 播放的链接
同样不支持。

**直播流？**
没有结束标记（缺 `EXT-X-ENDLIST`）的播放列表属于直播，FluxKit 不支持录制直播，会明确提示。

**能后台下载吗？**
直链下载使用后台会话，App 被挂起时也能继续完成。HLS 下载在系统挂起 App 时暂停，回到前台后从最后一个
完成的分片继续——暂停、崩溃或重启都不会从头再来。

**只想用 Wi-Fi？**
打开「设置 → 下载 → 仅 Wi-Fi」。蜂窝网络下任务会停在队列并给出提示，不会偷跑流量。

**买了 Pro 却没生效？**
打开「设置 → 升级」（或付费页）点**恢复购买**。购买由 Apple 通过你的 Apple ID 处理，请确认设备
登录的是购买时用的那个 Apple ID。

**如何管理或取消订阅？**
iOS「设置 → Apple ID → 订阅」，或 https://apps.apple.com/account/subscriptions 。删除 App
不会取消订阅。退款由 Apple 处理。

**免费版和 Pro 的区别？**
下载、HLS、字幕、画中画、文件访问都免费，同时下载 1 个。FluxKit Pro（按月或按年，自动续期）
把队列提高到同时 4 个，并开启播客自动下载。

**通知**
下载完成/失败通知默认关闭，可在「设置 → 通知」开启；只有在你开启时 App 才会请求通知权限。

**隐私一句话**
没有账号、没有分析、没有广告、没有追踪。链接直接向源站请求，不会发给我们。详见
[隐私政策](/privacy-policy)。
