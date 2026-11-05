# 冒烟测试报告（SMK-01..10）

| 项目 | 值 |
|---|---|
| 执行时间 | 2026-11-06 03:57 – 04:12（本机时间）|
| 构建 | Debug，`cloud.fluxkit.app`，1.0.0 (1) |
| 设备 | iPhone 18 Pro Max 模拟器（iOS 26 运行时）|
| 数据 | 清空容器后重装（`simctl uninstall` + `install`），3 次独立运行 |
| 结论 | **7 条通过 / 1 条修复后通过 / 2 条需真机** |
| 期间发现 | **P0 崩溃 ×1（已修复）**、**P2 文件泄漏 ×1（待修）**、P3 估算偏差 ×1 |

---

## 一、结果总览

| ID | 场景 | 结果 | 证据 |
|---|---|---|---|
| SMK-01 | 冷启动到首页可交互 | ✅ | XCUITest `testHomeShowsCoreActions` / `testHomePasteFillsTheLinkField` 通过；`LaunchPerformanceTests` 通过 |
| SMK-02 | 直链 MP4 → 下载 → 完成 | ✅ | `SMOKE: PASS … file=sample 5s.mp4 bytes=2848208 thumb=… duration=5.71` |
| SMK-03 | HLS 多码率 → 下载 | ⚠️→✅ | 初次 **崩溃**（见二）；修复后 `SMOKE: PASS … file=Video from devstreaming-cdn.apple.com.mp4 bytes=599863325 duration=600.02`，并生成字幕旁挂 `6118FDDF-….en.vtt`（28 KB）|
| SMK-04 | 暂停 → 续传 | ✅（附带缺陷）| `SMOKE: resumed` → `PASS bytes=2848208`；但残留孤儿文件（见三）|
| SMK-05 | 播客 feed → 单集下载 | ✅ | feed 解析出最新一期 `The history of light (classic)` 20,264,002 B → `PASS bytes=22931822 duration=1433.2`，文件名友好 |
| SMK-06 | 片库搜索 / 多选 | ✅ | `testLibrarySearchFiltersSeededItems`、`testLibrarySelectionModeIsAvailable` 通过 |
| SMK-07 | Paywall 显示价格与恢复购买 | ✅ | `testPaywallOpensFromSettings`、`testProUnlockHidesUpgradeButton` 通过（StoreKit 本地配置生效）|
| SMK-08 | 分享扩展写入 → 主 App 消费 | ✅（模拟器降级）| `INBOX: pushed … (pending=1)` → `INBOX: … pending=0`；模拟器无 App Group entitlement（`available=false`），真实容器路径需真机复核 |
| SMK-09 | 后台音频 + 锁屏控制 | ⏸ 需真机 | 模拟器无锁屏/耳机事件 |
| SMK-10 | 杀进程重启后数据完整 | ✅ | 重启后 `records: 3`，全部 `finished`，文件与字幕均在位 |

---

## 二、P0 崩溃（已修复）：HLS 字幕 `X-TIMESTAMP-MAP` 键序

**现象**：下载 Apple 官方示例流（`img_bipbop_adv_example_fmp4/master.m3u8`）时 App 直接崩溃，记录卡在 `running`、`fileName=None`，磁盘上留下 599 MB 的半成品。

**崩溃日志**（`FluxKit-2026-11-06-035950.ips`）：

```
EXC_BREAKPOINT / SIGTRAP   (Swift runtime trap)
  WebVTTParser.timestampMapOffset(in:)
  WebVTTParser.merge(segments:)
  HLSDownloader.downloadSubtitles(_:recordID:)
  HLSDownloader.download(playlistURL:recordID:fileName:progress:)
  DownloadManager.startHLS(record:media:)
```

**根因**：解析器假设键序固定为 `LOCAL:…,MPEGTS:…`，用

```swift
header[localPart.upperBound..<mpegPart.lowerBound]   // 若 MPEGTS 在前 → 无效 Range → trap
```

而 Apple 的字幕分片实际内容是：

```
WEBVTT
X-TIMESTAMP-MAP=MPEGTS:900000,LOCAL:00:00:00.000
```

**修复**：改为「按分隔符取值，与键序无关」，并对缺失/非数字值返回 `nil`（`WebVTTParser.timestampMapOffset`）。新增 4 条测试：两种键序、非零 LOCAL、6 种畸形头（含空值、非数字 MPEGTS）、跨分片混合键序的 offset 合并。修复后同一条流 `PASS`。

**回归风险**：任何带 WebVTT 字幕 rendition 的 HLS 流都会命中——包括苹果审核常用的示例流，属上架阻断级缺陷。

---

## 三、P2 缺陷（待修）：暂停/续传残留孤儿文件

**复现**：`SMOKE_PAUSE=1` + 直链 MP4。

**结果**：下载完成后 Media 目录里同时存在

```
sample 5s.mp4        2,848,208 B   04:05   ← 未被任何记录引用
sample 5s (2).mp4    2,848,208 B   04:05   ← 记录指向这个
```

记录的 `fileName` 是带 ` (2)` 的那个，第一个文件成了**永不清理的孤儿**（`Records` 引用集合校验：`孤儿文件: ['sample 5s.mp4']`）。

**影响**：每次暂停/续传（或续传失败后重下）都可能多留一份完整媒体文件 → 磁盘无声增长；片库重名时会不断产生 `(2)`、`(3)`。

**建议方向**：续传应以记录的 `fileName` 为唯一落点（resume 只改内容不改名），或在换名成功后删除旧文件；同时在「删除记录」和启动清理时按引用集合回收孤儿（可加一条启动时的一致性扫描）。

---

## 四、P3 观察

1. **HLS 大小估算偏低**：估算 585,499,767 B，实际 599,863,325 B（+2.4%）。进度因此在结尾处超过 100%（`bytesReceived > bytesExpected`）。建议进度上限钳制到 1.0，或在完成时用实际大小覆盖估算。
2. **播客缩略图为空**：冒烟路径下 `thumb=-`（`docs/ROADMAP.md` 声称下载完成时保存封面）。需在真机/带封面的 feed 上复核是路径问题还是 feed 缺 `itunes:image`。
3. **模拟器 App Group 不可用**：`INBOX: available=false`。这是模拟器未签名 entitlement 的预期行为，但意味着分享扩展的**跨进程**路径只能在真机验证。

---

## 五、需真机补测（提交审核前必须完成）

| 项 | 为什么必须真机 |
|---|---|
| SMK-09 后台音频 / 锁屏 / 耳机控制 | 模拟器无锁屏与远程控制事件 |
| SMK-08 分享扩展真实容器 | App Group 需要已签名 entitlement |
| SMK-03 后台继续下载 + 挂起恢复 | 后台 URLSession 在模拟器行为不完整 |
| 沙盒订阅：购买 / 恢复 / 取消 / 退款 | 模拟器无真实 StoreKit 沙盒账号 |
| 磁盘满、低内存、来电打断 | 需要真实硬件与系统事件 |

---

## 六、复跑方式（可重复）

```bash
# 0) 干净安装
xcodebuild -project FluxKit.xcodeproj -scheme FluxKit -configuration Debug \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' build
xcrun simctl uninstall booted cloud.fluxkit.app
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/FluxKit-*/Build/Products/Debug-iphonesimulator/FluxKit.app

# 1) SMK-02 直链
SIMCTL_CHILD_SMOKE_URLS="https://download.samplelib.com/mp4/sample-5s.mp4" \
  xcrun simctl launch booted cloud.fluxkit.app --smoke-test

# 2) SMK-03 HLS（含字幕 rendition，崩溃回归用例）
SIMCTL_CHILD_SMOKE_URLS="https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8" \
  xcrun simctl launch booted cloud.fluxkit.app --smoke-test

# 3) SMK-04 暂停/续传
SIMCTL_CHILD_SMOKE_PAUSE=1 SIMCTL_CHILD_SMOKE_URLS="https://download.samplelib.com/mp4/sample-5s.mp4" \
  xcrun simctl launch booted cloud.fluxkit.app --smoke-test

# 4) SMK-05 播客
SIMCTL_CHILD_SMOKE_URLS="https://feeds.npr.org/510289/podcast.xml" \
  xcrun simctl launch booted cloud.fluxkit.app --smoke-test

# 5) SMK-08 inbox
SIMCTL_CHILD_INBOX_PUSH="https://download.samplelib.com/mp4/sample-5s.mp4" \
  xcrun simctl launch booted cloud.fluxkit.app

# 6) 读日志
xcrun simctl spawn booted log show --last 3m \
  --predicate 'eventMessage CONTAINS "SMOKE:"' --style compact | grep "SMOKE:"

# 7) 校验落盘与索引
C=$(xcrun simctl get_app_container booted cloud.fluxkit.app data)
ls -la "$C/Documents/FluxKit/Media"
python3 -c "import json;d=json.load(open('$C/Library/Application Support/FluxKit/library.json'));print(len(d['records']))"
```
