# 广告位设计（Ads placement）

当前 App **不含任何广告 SDK**，`AdsConfig.isEnabled = false`，界面上不会出现广告。
但广告位已经按下面的方案预埋好（`SponsorSlot`），接入时只需要替换一处视图、填 unit ID、
把开关打开即可。

## 一、放哪里（推荐顺序）

| 优先级 | 位置 | 代码位置 | 形式 | 说明 |
|---|---|---|---|---|
| A（主） | 首页输入卡下方、进行中任务之后 | `HomeView` → `SponsorSlot(style: .banner)` | 自适应 banner（高 64） | 用户完成「粘贴→下载」动作的必经路径，曝光稳定且不挡操作 |
| B | 「任务」页已完成列表底部 | `DownloadsView` → `SponsorSlot(style: .banner)` | banner | 等待/回看下载时出现，属于「完成后的休息点」 |
| C | 「片库」网格底部 | `LibraryView` → `SponsorSlot(style: .native)` | 原生卡片（高 96） | 浏览已下载内容时展示，原生样式更贴合列表 |
| D（可选） | 下载完成后插屏 | 未实现 | interstitial | 建议限频：每 3 次完成最多 1 次、且当前无进行中任务、可立即关闭。首版不建议 |

**不要放**的位置（体验与审核风险）：

- 播放器内 / 全屏播放页：用户是为离线看视频来的，插广告会直接导致差评。
- 链接预览弹窗（`MediaPreviewSheet`）：会挡住「开始下载」按钮，属于误触。
- 输入框与「下载」按钮之间：同上。
- 冷启动立即插屏：审核与体验都不友好。
- 空状态页（片库/任务为空）铺广告：显得廉价，且没有内容上下文。

## 二、接入步骤（以 Google AdMob 为例）

1. **加 SDK**：Xcode → Package Dependencies → 添加
   `https://github.com/googleads/swift-package-manager-google-mobile-ads`
   （或 Firebase AdMob）。工程目前零第三方依赖，接入后需更新 `THIRD_PARTY_NOTICES`。
2. **Info.plist**：
   - `GADApplicationIdentifier` = 你的 AdMob App ID
   - `SKAdNetworkItems`：把 AdMob 文档里的全部 SKAdNetwork ID 加进去（否则归因失效）
3. **启动初始化**：在 `FluxKitApp` 启动时调用
   `MobileAds.shared.start()`（或 Firebase 等价 API）。
4. **替换占位视图**：编辑 `Sources/Ads/SponsorSlot.swift`，把 `placeholder`
   换成 `BannerView` / `NativeAdView`，unit ID 从 `AdsConfig` 读取。
5. **打开开关**：`AdsConfig.isEnabled = true`，并把三个 unit ID 换成生产 ID。
6. **本地预览**：Debug 下设置环境变量 `SHOW_AD_SLOT=1` 可看到虚线占位（无需 SDK），
   用来检查布局与留白。

> 三个预埋位置已经固定高度（banner 64 / native 96），替换成真实 SDK 视图时保持同样高度，
> 避免内容跳动。

## 三、合规与上架必做

| 项目 | 要求 |
|---|---|
| ATT（个性化广告） | 使用 IDFA 前必须弹 App Tracking Transparency 并写入 `NSUserTrackingUsageDescription`；用户拒绝后只能投非个性化广告。不想处理 ATT 就只投非个性化 |
| UMP / 同意管理 | 面向 EEA/UK 时必须接 Google UMP（或自有 CMP）先取同意再初始化广告 |
| App Privacy 标签 | 有广告后通常要声明 **Identifiers（设备 ID）** 与 **Advertising Data**（视 SDK 而定），并更新隐私清单 |
| 隐私清单 | 广告 SDK 自带 `PrivacyInfo.xcprivacy`；确认版本已包含，否则上传会被提示 ITMS-91053 |
| 年龄分级 | App Store 问卷中「是否包含广告」选是；含广告后分级可能变化 |
| 审核备注 | 说明广告只在列表/输入页展示，不在播放器内，可关闭 |
| 儿童 | 不要面向儿童投放；如需，使用 child-directed 设置 |
| 内容政策 | 下载类 App 不得用广告引导侵权内容；保持「仅下载有权保存的视频」提示 |

## 四、体验与收益建议

- **先 banner，后 native**：banner 实现简单、填充率高；native 的 eCPM 更好但需要样式适配。
- **限制插屏频率**：如启用 D，用 `UserDefaults` 记录上次展示时间，至少间隔 3 次下载 / 10 分钟。
- **不要在「解析中」展示**：`isResolving` 时隐藏广告，避免用户把加载失败归因于广告。
- **广告加载失败要静默**：占位高度保留、显示背景色即可，不要弹出错误。
- **首版可以不开**：先验证留存，等 DAU 稳定后再开 A/B（`AdsConfig.isEnabled` 可配合远程开关）。
- **付费去广告（可选）**：后续可加一次性内购 `Remove Ads`，用 `StoreKit 2` 读取权益后隐藏
  `SponsorSlot`；这是比插屏更健康的变现方式。

## 五、当前代码状态

- `Sources/Ads/AdsConfig.swift`：总开关 + unit ID 占位 + Debug 预览开关
- `Sources/Ads/SponsorSlot.swift`：唯一广告视图（banner / native 两种高度）
- 预埋点：`HomeView`、`DownloadsView`、`LibraryView`
- 未接入任何 SDK，App 体积与隐私标签不受影响
