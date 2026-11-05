# FluxKit Pro：StoreKit 2 + RevenueCat 配置

订阅使用 **StoreKit 2 商品 + RevenueCat SDK**：购买仍然走 Apple，RevenueCat 负责收据校验、
entitlement 同步、跨设备恢复和 Offering 管理。App 内不保存任何收据或密钥。

## 1. App Store Connect：创建商品

在订阅组（例如 `FluxKit Pro`）下创建两个自动续期商品：

| 商品 ID | 周期 |
|---|---|
| `cloud.streamkit.pro.monthly` | 1 个月 |
| `cloud.streamkit.pro.yearly` | 1 年 |

- 填写价格、本地化（en-US / zh-Hans）、审核截图。
- 在 App 版本页把两个商品加入「App 内购买项目」。
- 生成 **App Store Connect API Key** 或共享密钥，供 RevenueCat 校验收据。

## 2. RevenueCat：项目与 Offering

1. 新建 Project → 添加 iOS App，Bundle ID 填 `cloud.streamkit.app`。
2. 在 App 设置里填入 App Store Connect 的共享密钥/API Key。
3. **Products**：导入上面两个商品。
4. **Entitlements**：新建 entitlement，identifier 必须是 **`pro`**
   （`ProConfig.entitlementID`），把两个商品都挂到它上面。
5. **Offerings**：新建 offering（设为 Current，identifier 建议 `default`），
   添加两个 package：
   - `$rc_monthly` → `cloud.streamkit.pro.monthly`
   - `$rc_annual` → `cloud.streamkit.pro.yearly`
6. 复制 **public SDK key**：
   - 开发/测试：使用 **Test Store** 的 key（`test_…`），购买是模拟的，不经过 App Store；
   - 上架：使用 Apple 平台的 public key（`appl_…`）。
7. 把 key 写入 `project.yml`：

   ```yaml
   REVENUECAT_API_KEY: "appl_xxxxxxxxxxxxxxxx"   # 上架
   # REVENUECAT_API_KEY: "test_xxxxxxxxxxxxxxxx" # 仅 Debug 测试
   ```

   然后 `xcodegen generate`。这个 key 是公开的，可以进仓库；不要填 secret key。

> **注意**：`test_` 开头的 Test Store key 只能在 Debug 使用。代码在 Release 构建里会把它视为未配置，
> 避免误把测试购买带上架；上架前务必替换成 `appl_` key。

## 3. 代码结构

| 文件 | 作用 |
|---|---|
| `Sources/Core/ProStore.swift` | `Purchases.configure`、offerings、purchase、restore、customerInfoStream、entitlement → `isPro` |
| `Sources/Core/ProEntitlements.swift` | 免费/Pro 的纯逻辑门控（并发、自动下载），有单测 |
| `Sources/Views/PaywallView.swift` | 读取 RevenueCat packages，展示价格并购买 |
| `Sources/Views/SettingsView.swift` | Pro 卡片、恢复购买、锁定提示 |

- 免费：同时 1 个下载，播客自动下载关闭。
- Pro：1–4 个并发、播客自动下载 1/3/5 期。
- 订阅状态来自 `CustomerInfo.entitlements.active["pro"]`，并通过
  `Purchases.shared.customerInfoStream` 实时更新。
- 没有配置 `REVENUECAT_API_KEY` 时，App 不会初始化 SDK，Paywall 显示
  “RevenueCat isn't configured in this build”，CI/截图不受影响。

## 4. 本地测试（Test Store）

1. 使用 RevenueCat 后台的 **Test Store key**（`test_…`）填 `REVENUECAT_API_KEY`。
2. 在 RevenueCat 的 **Test Store** 里创建两个测试商品，并挂到 entitlement `pro`、
   Current Offering 的 `$rc_monthly` / `$rc_annual` 两个 package 上。
3. 生成工程、运行 App，购买会走 Test Store（模拟成功，不扣款）。
4. 上架前把 key 换成 `appl_…`，商品换成 App Store Connect 的真实商品。

### 使用 Sandbox / 真实商品

1. 用 `appl_` key 配置 `project.yml` 并生成工程。
2. 在 RevenueCat 后台创建 **Test Store**（或使用 Sandbox 测试账号）。
3. Xcode 登录 Sandbox 账号（Settings → Accounts），或使用 RevenueCat Test Store 进行测试购买。
4. 运行 App → Settings → Upgrade → 选择月/年 → 完成购买；
   检查 Settings 的 Pro 状态和 4 并发是否解锁。
5. 恢复购买：删除 App 重装 → Paywall → Restore purchases。
6. Debug 快捷开关：
   - `-proUnlocked`：强制 Pro（UI 测试/截图）
   - `-showPaywall`：启动后直接打开 Paywall

## 5. 隐私与审核

RevenueCat 会收集：匿名 App User ID、购买记录、设备/系统信息，用于收据校验和订阅同步。
需要：

- App Privacy 中声明 **Purchases**（以及 RevenueCat 文档建议的 Identifiers/Diagnostics）。
- 隐私政策里说明使用了 RevenueCat 作为订阅管理服务，并链接其隐私政策。
- Paywall 展示价格、周期、自动续期说明、恢复购买、使用条款与隐私政策链接
  （`SKTermsURL` / `SKPrivacyPolicyURL`）。
- 审核备注说明订阅权益，核心下载功能免费可用。

## 6. 上架检查

- [ ] `REVENUECAT_API_KEY` 已填，且是 public key
- [ ] RevenueCat entitlement identifier = `pro`
- [ ] Offering 已设为 Current，包含月/年 package
- [ ] App Store Connect 商品已通过审核（首次需随 App 一起提交）
- [ ] `SKTermsURL` / `SKPrivacyPolicyURL` 可访问
- [ ] App Privacy 已更新（Purchases）
- [ ] Restore purchases 可用
