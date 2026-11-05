# FluxKit 上架手把手（Apple 后台 + RevenueCat）

> 适用版本：2025/2026 的 App Store Connect 与 RevenueCat 控制台。
> 界面文案可能随 Apple/RevenueCat 更新略有变化，但入口和字段基本一致。
> 本文默认：App 名称 `FluxKit`，Bundle ID `cloud.fluxkit.app`，Team `H5YQ9HSATA`。

---

## 0. 先准备这 6 样东西

| 准备项 | 说明 |
|---|---|
| Apple Developer Program | 付费账号（个人 $99/年；公司需 D-U-N-S） |
| 已签协议 + 税务 + 银行 | App Store Connect → **Business / Agreements**；订阅必须签 **Paid Applications** 协议 |
| 隐私政策 URL | 必须公网可访问；可用 GitHub Pages（模板见 `docs/privacy-policy.md`） |
| 使用条款 URL | 订阅类 App 必需；可用 Apple 标准 EULA 或自己的条款（模板见 `docs/terms-of-use.md`） |
| 6.9" 截图 | 1320×2868；用 iPhone 16 Pro Max / 17 Pro Max 模拟器或真机截图，至少 3 张 |
| 1024×1024 图标 | 不能有透明通道（本仓库图标已符合） |

> 提醒：不要把 Apple ID / RevenueCat 密码发给任何人。测试用的 `test_` key 是公开的，
> 但 `sk_` Secret Key、`.p8` 私钥、账号密码都不能进仓库或聊天。

---

# 第一部分：Apple 后台

## 1. 注册 Bundle ID 与 App Group

**路径**：developer.apple.com → Certificates, Identifiers & Profiles

1. 左侧 **Identifiers** → 右上角 **＋**。
2. 选 **App IDs** → **App** → Continue。
3. 填写：
   - Description：`FluxKit`
   - Bundle ID：**Explicit**，填 `cloud.fluxkit.app`
4. Capabilities 勾选：
   - **App Groups**（重要，分享扩展要用）
   - 其它保持默认
5. Continue → Register。
6. 再注册分享扩展的 Bundle ID：
   - `cloud.fluxkit.app.share`（同样勾 App Groups）
7. 左侧 **Identifiers → App Groups** → **＋**：
   - Identifier：`group.cloud.fluxkit.app`
   - 注册后回到两个 App ID，把该 App Group 勾上并 Save。

> Xcode 自动签名通常也会帮你创建这些，但提前建好更稳。

## 2. 创建 App Store Connect API Key（给 RevenueCat 用）

**路径**：App Store Connect → **Users and Access** → **Integrations**（旧版叫 Keys）

1. 选择 **App Store Connect API** → **Team Keys** → **＋**。
2. Name：`RevenueCat`
3. Access：**App Manager**（或 Admin，权限越大越省事，但最小权限用 App Manager）。
4. 生成后记下：
   - **Issuer ID**（页面顶部）
   - **Key ID**
   - 下载 **`.p8` 文件**（只能下载一次）
5. 这三个东西填到 RevenueCat（后面第 4 部分）。

> 如果你不想用 API Key，RevenueCat 也支持旧的 **Shared Secret**（App Store Connect →
> App 信息 → App Store Server Notifications / App-Specific Shared Secret），但推荐 API Key。

## 3. 创建 App Store Connect App 记录

**路径**：App Store Connect → **Apps** → **＋** → **New App**

| 字段 | 填什么 |
|---|---|
| Platform | iOS |
| Name | `FluxKit: HLS & Podcast Saver`（≤30 字符） |
| Primary Language | English (U.S.) |
| Bundle ID | `cloud.fluxkit.app` |
| SKU | `fluxkit-ios-001`（自己记好，唯一即可） |
| User Access | Full Access |

创建后进入 App 页面，先填 **App Information**：

| 字段 | 值 |
|---|---|
| Name / Subtitle | 名称同上；副标题 `Save HLS, links & podcasts.`（≤30） |
| Category | Primary：**Utilities**；Secondary：Productivity |
| Content Rights | 见下方说明 |
| Age Rating | 点 **Edit**，按问卷填写（无成人内容；含 App 内购买 → 通常 4+） |

**Content Rights（内容版权）**：选 **Yes**。题目原话是 “Does your app contain, show, or access
third-party content?”，关键词是 **access**。FluxKit 虽不内置任何内容，但会按用户提供的链接
请求/播放第三方服务器上的媒体，属于 access。选 No 与事实不符，会被按 2.3.1 元数据不准确处理。
选 Yes 后按 `docs/STORE_REVIEW_NOTES.md` 的 “Content rights” 段落粘贴说明即可。

**年龄分级里的 “Unrestricted Web Access”**：选 **No**（无 WebView、不渲染网页，只对 URL 发请求）。

## 4. 定价与销售范围

**路径**：App 页面 → **Pricing and Availability**

- Price：**Free**
- Availability：选择首发国家（建议 United States + 主要英语国家）
- 如果以后加 Pro 订阅，App 本身仍可免费。

## 5. 创建订阅（FluxKit Pro）

**路径**：App 页面 → 左侧 **Monetization → Subscriptions**（旧版在 **Features → In-App Purchases**）

1. 点 **Create Subscription Group**：
   - Reference Name：`FluxKit Pro`
   - 保存后添加本地化名称（English：`FluxKit Pro`；简体中文：`FluxKit Pro`）
2. 在组内点 **Create** 创建两个自动续期订阅：

| 字段 | 月付 | 年付 |
|---|---|---|
| Reference Name | `FluxKit Pro Monthly` | `FluxKit Pro Yearly` |
| Product ID | `cloud.fluxkit.pro.monthly` | `cloud.fluxkit.pro.yearly` |
| Subscription Duration | 1 Month | 1 Year |

3. 每个订阅分别填：
   - **Subscription Prices**：选价格（可先设 $2.99/月、$19.99/年，后续随时改）
   - **Localizations**：至少 English (U.S.) 与简体中文；显示名称 ≤30 字符，描述 ≤45 字符
   - **Review Information**：上传一张 Paywall 截图（Pro 页面）
   - **Availability**：与 App 一致
4. 两个订阅的状态最终要变成 **Ready to Submit**。
5. 回到 App 版本页（**App Store** 标签 → 版本），在 **In-App Purchases and Subscriptions**
   区域点 **Add**，把两个订阅加进这个版本（首次订阅必须随 App 一起送审）。

## 6. App Privacy（隐私标签）

**路径**：App 页面 → 左侧 **App Privacy** → **Get Started**

RevenueCat 会处理购买信息，因此通常要声明：

| 数据类型 | 是否收集 | 用途 | 关联到用户 | 用于追踪 |
|---|---|---|---|---|
| **Purchases → Purchase History** | 是 | App Functionality | 否（匿名 App User ID） | 否 |
| **Identifiers → User ID**（RevenueCat 匿名 ID） | 按 RevenueCat 建议 | App Functionality | 否 | 否 |
| **Diagnostics**（可选，SDK 诊断） | 按实际情况 | App Functionality | 否 | 否 |

- **不要**勾选“用于追踪/广告”，本 App 没有 ATT。
- 麦克风/相册等权限不算“收集”，因为数据不上传。
- 完成后保存；必须与隐私政策一致。

> RevenueCat 官方有一份 “App Privacy” 指南，若不确定，照它最新表格勾选。

## 7. 版本页素材

**路径**：App 页面 → **App Store** → 版本（例如 1.0）

| 字段 | 内容 |
|---|---|
| Promotional Text | `fastlane/metadata/en-US/promotional_text.txt` |
| Description | `fastlane/metadata/en-US/description.txt` |
| Keywords | `hls downloader,m3u8,mp4,mp3,podcast downloader,offline media,media saver,direct link,audio,video` |
| Support URL | 你的支持页（必须可访问） |
| Marketing URL | 可选 |
| Privacy Policy URL | 你的隐私政策（必须） |
| Screenshots | 6.9" 至少 3 张；建议 5 张：首页、播客、下载队列、片库、Paywall |
| App Preview | 可选（15–30 秒） |

**截图尺寸**：6.9" = **1320×2868**。本仓库 `docs/screenshots` 是 1206×2622（6.3"），
上传前请用 iPhone 16/17 Pro Max 重新截图，或用营销截图工具导出正确尺寸。

## 8. 出口合规 / 加密

- 项目已在 Info.plist 设置 `ITSAppUsesNonExemptEncryption = false`
  （只使用系统 HTTPS，无自研加密）。
- 上传后在版本页确认 **Export Compliance** 不需要额外问卷；如果出现，选
  “Uses encryption? No / Exempt”。

---

# 第二部分：RevenueCat 后台

> 你现在用的是 `test_` 开头的 **Test Store** key，购买是模拟的。
> 正式上架必须再建一个 **App Store** 类型的 App，使用 `appl_` key。

## 1. 创建项目

RevenueCat → **Projects** → **＋ New Project**：

- Name：`FluxKit`
- 进入项目。

## 2. 添加 App Store App（正式）

项目页 → **Apps** → **＋ New App**：

| 字段 | 值 |
|---|---|
| App name | `FluxKit` |
| Platform | **App Store** |
| Bundle ID | `cloud.fluxkit.app` |
| App Store Connect API Key | 填第一部分生成的 **Issuer ID / Key ID / .p8** |

保存后 RevenueCat 会尝试连接 App Store Connect；连接成功会显示绿色状态。

> 如果同时保留 Test Store App，它和 App Store App 是同一项目下的两个 App；
> 开发用 Test Store key，上架用 App Store key。

## 3. 导入商品

**Products** → **Import from App Store**：

- 勾选 `cloud.fluxkit.pro.monthly`、`cloud.fluxkit.pro.yearly` → Import。
- 如果商品还没在 App Store Connect 创建，先回第一部分第 5 节。

## 4. 创建 Entitlement

**Entitlements** → **＋ New**：

- Identifier：**`pro`**（必须与代码 `ProConfig.entitlementID` 完全一致）
- Description：`FluxKit Pro`
- Attach products：把月付、年付都加上。

## 5. 创建 Offering

**Offerings** → **＋ New**：

- Identifier：`default`
- 右上角 **Make Current**（必须 Current，否则 App 拿不到 packages）
- **Add Package**：
  - 选 **Monthly** → 选择 `cloud.fluxkit.pro.monthly`
  - 选 **Annual** → 选择 `cloud.fluxkit.pro.yearly`
- 保存后确认页面显示两个 package 且 offering 为 Current。

## 6. 获取 Public SDK Key

**Project settings → API keys**（左侧齿轮）：

- **App Store** App 的 public key：`appl_…` → 上架用
- **Test Store** 的 key：`test_…` → 开发用（你现在的）

把正式 key 填进 `project.yml`：

```yaml
REVENUECAT_API_KEY: "appl_你的生产Key"
```

然后：

```bash
xcodegen generate
```

> `sk_` Secret Key 只用于服务端/脚本，绝不进 App。

## 7. App Store Server Notifications（推荐）

RevenueCat 项目设置 → **App Store Server Notifications**：

- 复制 RevenueCat 提供的 **V2 URL**；
- 回 App Store Connect → App 信息 → **App Store Server Notifications**：
  - Production URL 填 RevenueCat 的 V2 URL
  - 选择 Version 2
  - 保存

这样退款、续费、取消等状态能实时同步。

## 8. 测试购买

### Test Store（现在就能测）

1. 确认 Test Store App 里建了测试商品，并挂到 `pro` entitlement 与 Current Offering。
2. 用 `test_` key 跑 App → Settings → Upgrade → 购买（模拟成功）。
3. 验证 Settings 显示 Pro Active、并发可调到 4、播客自动下载可选。

### Sandbox（TestFlight/真机）

1. App Store Connect → **Users and Access → Sandbox → Testers** 创建测试账号。
2. 真机/TestFlight 登录沙盒账号（设置 → App Store → 沙盒账户）。
3. 用 `appl_` key 构建并安装 App，购买会走 Sandbox（不扣款）。
4. 测试：购买、取消、恢复购买、跨设备恢复。

---

# 第三部分：构建、上传、TestFlight

## 1. 归档

```bash
cd fluxkit-ios   # 仓库目录；如果你的文件夹已改名，用你本地的名字
xcodegen generate
xcodebuild -project FluxKit.xcodeproj -scheme FluxKit \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/FluxKit.xcarchive archive -allowProvisioningUpdates
```

> 需要 Xcode 已登录 `H5YQ9HSATA` 对应的 Apple ID，并生成/下载 Distribution 证书。

## 2. 上传

- 打开 Xcode → **Window → Organizer** → 选中 Archive → **Distribute App** →
  **App Store Connect** → Upload。
- 或用 `xcodebuild -exportArchive` 导出 IPA，再用 **Transporter** 上传。

## 3. TestFlight

1. App Store Connect → **TestFlight** → 等待构建处理完成（几分钟）。
2. **Internal Testing**：加自己/团队，立即测试。
3. **External Testing**：创建测试组，提交 **Beta App Review**（通常 1–2 天）。
4. 测试重点：
   - HLS/直链下载、暂停/续传、后台下载
   - 播客订阅、OPML、自动下载
   - 字幕、画中画、后台音频
   - Pro 购买/恢复（Sandbox）
   - Files App 可见与导入

---

# 第四部分：提交审核

## 1. 版本页检查

- Build：选择刚上传的构建
- In-App Purchases and Subscriptions：两个订阅都已添加
- App Privacy：已保存
- Age Rating：已完成
- Export Compliance：已确认
- 截图/描述/关键词/URL：已填
- **Release**：建议先选 **Manually release**，审核通过后自己点发布

## 2. 审核备注（直接粘贴，按实际修改）

```
FluxKit is an offline media saver for content the user is allowed to keep:
HLS (.m3u8) playlists, direct MP4/MOV/WebM/MP3/M4A links, podcast RSS/Atom feeds,
and files imported from the Files app.

It does NOT break DRM, bypass logins/paywalls, remove watermarks, or extract media
from platform-locked services. Links that only play inside another company's app
are rejected with an explanation.

To test:
1. Paste a public HLS test stream:
   https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8
2. Paste a public MP4:
   https://download.samplelib.com/mp4/sample-5s.mp4
3. Podcast: https://feeds.npr.org/510289/podcast.xml
4. Subscriptions: Settings → Upgrade → monthly/yearly (Sandbox).

FluxKit Pro is an auto-renewable subscription that unlocks 4 simultaneous downloads
and podcast auto-download. Core downloading, HLS, subtitles, PiP, and Files access
are free. Restore purchases is available on the paywall and in Settings.

No account, no analytics SDK, no tracking. RevenueCat is used for subscription
receipt validation with an anonymous app user ID.
```

## 3. 订阅审核注意

- 首次订阅必须和 App 版本一起提交；订阅状态为 **Ready to Submit**。
- Paywall 必须显示：价格、周期、自动续期、恢复购买、条款/隐私链接。
- 如果被拒 3.1.2：检查是否有“Restore purchases”、条款链接、订阅说明。

## 4. 常见拒审与处理

| 拒审理由 | 处理 |
|---|---|
| **5.2.3 版权/下载** | 强调只处理用户提供的直链/HLS/播客；不解析平台受限链接、不破 DRM；提供演示视频 |
| **4.2 最低功能** | 强调队列、播客、字幕、PiP、Files、Pro 等完整功能 |
| **2.3.1 元数据不准确** | 截图/描述与实际一致；不要写“下载任何视频” |
| **3.1.2 订阅** | 补 Restore、条款/隐私链接、价格与周期说明 |
| **2.1 崩溃** | 用 TestFlight 跑完整流程；检查 RevenueCat 未配置时的兜底 |
| **隐私标签不符** | 按 RevenueCat 实际收集项更新 App Privacy |

---

# 第五部分：上线检查清单

- [ ] Apple Developer 协议/税务/银行完成（Paid Apps）
- [ ] Bundle ID + App Group + 分享扩展注册
- [ ] App Store Connect App 记录、分类、年龄分级、Content Rights
- [ ] 两个订阅创建完成、本地化、价格、审核截图、Ready to Submit
- [ ] 订阅已加入 App 版本
- [ ] App Privacy 已按 RevenueCat 填写
- [ ] 隐私政策 / 使用条款 URL 可访问
- [ ] `appl_` key 填入 `project.yml`，`test_` key 只在 Debug
- [ ] RevenueCat：App Store App、商品导入、entitlement `pro`、Current Offering
- [ ] App Store Server Notifications V2 已配置（推荐）
- [ ] 6.9" 截图（1320×2868）与图标
- [ ] Archive 用 Distribution 证书签名并上传
- [ ] TestFlight 内测 + Sandbox 购买/恢复
- [ ] 审核备注、演示视频
- [ ] 选择手动发布；上线后监控崩溃与评论

---

## 附：常见后台报错对照

| 现象 | 原因 | 解决 |
|---|---|---|
| Paywall 显示 “RevenueCat isn't configured” | key 为空 / 填错 / Release 用了 `test_` | 填 `appl_` key，`xcodegen generate` |
| Paywall 显示 “No offerings” | Offering 未设为 Current / 没有 package | RevenueCat 里检查 Current Offering 与 package 映射 |
| 购买按钮灰色 | 商品未导入 / 未挂 entitlement / ASC 商品缺元数据 | 检查 Products、Entitlement、ASC 状态 |
| 订阅无法提交 | 缺审核截图/本地化/价格 | 补齐后状态变 Ready to Submit |
| TestFlight 构建不可选 | 处理中 / 出口合规未确认 | 等待处理，确认 Export Compliance |
| 上传报签名错误 | 缺 Distribution 证书 / 账号未登录 | Xcode → Settings → Accounts 登录并下载证书 |
| App Privacy 审核提问 | 未声明 Purchases | 按 RevenueCat 指南补 Purchase History/Identifiers |

---

需要我把这份流程按你的实际后台截图逐步标注、或生成可托管的隐私政策/条款页面，
告诉我即可（不要发送账号密码或 Secret Key）。
