# FluxKit 测试计划（v1.0 发布验证）

> 适用版本：`MARKETING_VERSION 1.0.0`，Bundle `cloud.fluxkit.app`，iOS 17.0+，仅 iPhone。
> 目标：在提交 App Store 审核前，用可重复的最小成本证明「功能正确、不崩、不卡死、无数据竞争、性能达标」。
>
> 用例 ID 前缀：`SMK`（冒烟）`IN`（输入解析）`DL`（直链下载）`HLS`（HLS）`POD`（播客）`PLY`（播放）
> `LIB`（片库）`SET`（设置）`PRO`（订阅）`SHR`（分享扩展）`PST`（持久化）`SITE`（站点解析）
> `CMB`（组合）`EDG`（边界）`PERF`（性能）`STA`（稳定性）`THR`（线程安全）`NET`（网络）
> `SYS`（系统事件）`CMP`（兼容/无障碍/本地化）`SEC`（安全隐私）

---

## 0. 基线现状与执行前必读

| 项目 | 状态 |
|---|---|
| 自动化测试 | 单元测试 14 个文件 / 77 条；UITest 6 条（首页、设置、片库搜索、多选、Paywall、Pro 状态） |
| 已覆盖较好的模块 | `LinkURL`/`LinkTextExtractor`、`LinkResolver`、`WebVTTParser`、`FeedParser`、`PersistedIndex`、`AppPaths` 迁移、`ProEntitlements`、`Settings`、`SiteExtractor`、`AESFixture` |
| 覆盖薄弱 | 下载状态机（URLSession 回调序列）、后台会话重连、HLS 断点续传、播放会话/PiP、分享扩展端到端、订阅真实链路、App Group 并发 |
| 已知未覆盖的非功能项 | 线程安全（TSan）、内存/泄漏、电量、弱网、磁盘满、看门狗卡顿 |
| ⚠️ 执行前提 | 测试必须在**能编译的提交**上跑。当前工作区存在未完成的重构（`Shared/LinkTextExtractor.swift:26` 静态 `NSRegularExpression` 未 `try`），编译会失败——先修好或 `git stash` 后再执行本计划 |

**环境要求**

| 类别 | 要求 |
|---|---|
| 真机 | 至少 1 台 iPhone（iOS 17.x 旧机或 SE 小屏）+ 1 台 iOS 最新版主力机 |
| 模拟器 | iPhone 18 Pro Max（已有）、iPhone SE（小屏）用于布局 |
| 账号 | 沙盒测试账号（非真实 Apple ID）、RevuteCat Test Store（Debug）与 App Store Sandbox（Release）两套 |
| 工具 | Xcode Instruments（Time Profiler / Allocations / Leaks / Animation Hitches / Energy）、Network Link Conditioner、Console.app、Transporter |
| 网络 | Wi-Fi（≥50Mbps）、蜂窝（可选）、弱网（NLC 1000ms/1% 丢包）、断网（飞行模式） |

---

## 1. 测试素材（Test Fixtures）

| 素材 | 用途 | 来源 |
|---|---|---|
| HLS 多码率（fMP4 + 字幕） | 主流程、码率选择、fMP4 直通 | `https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8` |
| HLS 多码率（TS） | MPEG-TS→MP4 remux | `https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8` |
| HLS 直播 | 直播拒绝提示 | 任一无 `EXT-X-ENDLIST` 的直播源（或本地 ffmpeg 生成，见下） |
| 直链 MP4 | 后台下载、断点续传 | `https://download.samplelib.com/mp4/sample-5s.mp4` |
| 大文件（>1GB） | 内存/断点/磁盘 | 自建 CDN 或 `https://speed.cloudflare.com/__down?bytes=1073741824` |
| 播客 RSS | 单集列表、自动下载 | `https://feeds.npr.org/510289/podcast.xml` |
| 网页内嵌视频 | 页面抓取（og:video / `<video>` / JSON-LD） | 自建静态页（推荐，可控制 meta 组合） |
| 站点解析器 | 好看/搜狐/百度/Reddit 四条路径 | `haokan.baidu.com`、`tv.sohu.com`、`mbd.baidu.com`、`reddit.com`（需当地可访问） |
| 加密 HLS（AES-128） | 解密路径 | 本地 ffmpeg 生成（见下） |

本地生成加密 / 字幕 / 直播流的命令（一次性，用于离线稳定回归）：

```bash
# AES-128 加密 VOD（生成 key 与 key_info）
printf '0123456789abcdef' > enc.key && printf 'enc.key\nenc.key\n' > key_info
ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=30 -t 20 -c:v libx264 -b:v 2M \
  -f hls -hls_time 2 -hls_playlist_type vod -hls_key_info_file key_info enc.m3u8

# 带字幕 rendition 的 HLS
ffmpeg -i in.mp4 -i sub.srt -c copy -c:s webvtt -f hls -hls_time 4 \
  -hls_subtitle_path subs -hls_playlist_type vod ts_subs.m3u8

# 直播（无 ENDLIST）：推流到本地 nginx-rtmp，或用
# ffmpeg -re -i in.mp4 -c copy -f hls -hls_time 2 -hls_list_size 3 live.m3u8

# 本地托管（HTTP，无 HTTPS）用于验证 ATS 放行
python3 -m http.server 8000
```

---

## 2. 冒烟测试（每次构建必跑，10 分钟，`SMK`）

任何一条失败即视为构建不可用，直接退回开发。

| ID | 场景 | 预期 |
|---|---|---|
| SMK-01 | 冷启动到首页可交互 | ≤2s，无白屏、无崩溃 |
| SMK-02 | 粘贴直链 MP4 → 预览 → 下载 → 完成通知 | 片库出现条目，可播放 |
| SMK-03 | 粘贴 HLS 多码率 → 下载 | 生成单一 `.mp4`，可播放且有声 |
| SMK-04 | 暂停 → 继续（直链 / HLS 各一次） | 从断点续传，不重下 0% |
| SMK-05 | 播客 feed → 单集下载 → 播放 | 节目列表有日期/时长/大小 |
| SMK-06 | 片库搜索 + 排序 + 删除 | 列表与存储统计同步更新 |
| SMK-07 | 设置 → Upgrade → Paywall 显示价格 | 有价格/周期/恢复购买/条款/隐私链接 |
| SMK-08 | Safari 分享链接到 FluxKit | 扩展显示成功，主 App 回前台自动填入 |
| SMK-09 | 后台播放 + 锁屏控制 | 锁屏显示标题/进度，可播放暂停与拖动 |
| SMK-10 | 杀进程重启 | 未完成任务标记为已暂停/已恢复，片库不丢 |

---

## 3. 功能测试用例

### 3.1 输入与链接解析（`IN`）

| ID | 步骤 | 预期 |
|---|---|---|
| IN-01 | 粘贴纯直链 `.mp4` | 直接进入预览，显示大小/类型 |
| IN-02 | 粘贴 `.m3u8` | 识别为 HLS，显示码率/分片估算 |
| IN-03 | 粘贴无 scheme 的 `v.douyin.com/x` | 自动补 `https://` 后判定为受限站点并提示 |
| IN-04 | 粘贴中文长文案内含一条链接 | 只提取链接，输入框被清理 |
| IN-05 | 文案内含 **两条** 链接 | 只取第一条，不报错 |
| IN-06 | 粘贴 `mailto:` / `file:` / `ftp:` / 纯电话号 | 明确拒绝，不发起请求 |
| IN-07 | 粘贴 HTML 网页（含 `og:video`） | 抓到媒体地址并预览 |
| IN-08 | 网页只含 `<video><source>` | 抓取成功 |
| IN-09 | 网页只含 JSON-LD `contentUrl` | 抓取成功 |
| IN-10 | 网页无任何媒体 | 明确提示「未找到媒体」，不下载 HTML |
| IN-11 | 平台受限链接（抖音/TikTok/YouTube/Instagram） | 立即拒绝并解释原因，无网络请求风暴 |
| IN-12 | 需要登录/付费墙的页面 | 明确提示不支持 |
| IN-13 | 链接返回 404/410 | 提示链接失效，可重试刷新地址 |
| IN-14 | 链接返回 403（防盗链） | 提示需 Referer/已过期，不无限重试 |
| IN-15 | 302 多跳重定向（≥3 跳） | 跟随成功，最终地址正确 |
| IN-16 | 极长 URL（>2000 字符）/ 含中文百分号编码 | 不崩溃，正常或明确报错 |
| IN-17 | 粘贴内容含 emoji / 换行 / 制表符 | 清理后正常解析 |
| IN-18 | 复制粘贴与「分享扩展」两条入口同一链接 | 结果一致（同一解析路径） |

### 3.2 直链下载（`DL`）

| ID | 步骤 | 预期 |
|---|---|---|
| DL-01 | 单任务下载 5s MP4 | 进度平滑，完成后通知（若开启） |
| DL-02 | 下载中按下 Home 键 | 后台继续；回前台进度正确 |
| DL-03 | 下载中锁屏 5 分钟 | 仍完成（后台会话） |
| DL-04 | 下载中杀进程 → 重启 App | 通过 `taskDescription` 重新匹配，状态正确不重复 |
| DL-05 | 暂停 → 继续（同网络） | 使用 resumeData，字节数从断点继续 |
| DL-06 | 暂停 → 换网络 → 继续 | 不崩溃；必要时从头重下并提示 |
| DL-07 | 取消任务 | 记录移除，临时文件清理 |
| DL-08 | 下载失败（断网） | 状态为失败，可重试；不无限重试 |
| DL-09 | 401/403/404/410/412/416/451 各一次 | 拒绝码映射到正确文案（单测已覆盖映射，此处验端到端） |
| DL-10 | 并发 1 / 2 / 3 / 4 任务 | 同时运行数符合设置；其余排队 |
| DL-11 | 队列中删除等待任务 | 后续任务自动补位 |
| DL-12 | 仅 Wi-Fi 打开 + 蜂窝 | 任务停在队列并提示，切换 Wi-Fi 后自动开始 |
| DL-13 | 文件名含 emoji / `/` `:` `?` / 超长标题 | 落地文件名合法、可播放、Files 中显示正常 |
| DL-14 | 同名文件二次下载 | 不覆盖原文件（自动加后缀） |
| DL-15 | 下载中被外部删除临时文件 | 失败并给出可恢复状态，不崩溃 |
| DL-16 | 下载完成后立即删除条目 | 文件与缩略图同时清理，无残留 |

### 3.3 HLS（`HLS`）

| ID | 步骤 | 预期 |
|---|---|---|
| HLS-01 | fMP4 主播放列表 | 选择最高码率，直通拼接，可播放有声 |
| HLS-02 | TS 主播放列表 | MPEG-TS → MP4 remux 成功，音画同步 |
| HLS-03 | 含独立音频 rendition | 音轨 mux 回视频，播放有音 |
| HLS-04 | AES-128 加密流 | 解密成功，内容可播放 |
| HLS-05 | SAMPLE-AES / SAMPLE-AES-CTR | 明确拒绝（unsupported），不产出坏文件 |
| HLS-06 | 无 `EXT-X-ENDLIST`（直播） | 提示不支持直播 |
| HLS-07 | `EXT-X-BYTERANGE` / `EXT-X-MAP` | 大小估算正确（不爆炸式估算） |
| HLS-08 | 分片 404（部分失败） | 失败可重试；已下分片不重下 |
| HLS-09 | 暂停 → 继续 | 从最后完成分片续传 |
| HLS-10 | 下载中杀进程 → 重启 | 中断任务标记为已暂停，继续后复用分片 |
| HLS-11 | 播放列表含字幕 rendition | 生成 WebVTT 旁挂文件，可选中显示 |
| HLS-12 | 300+ 分片长视频（≥1h） | 完成且内存稳定（配合 PERF-04） |
| HLS-13 | 主播放列表 302 到另一域名 | 相对/绝对分片地址都正确解析 |

### 3.4 播客（`POD`）

| ID | 步骤 | 预期 |
|---|---|---|
| POD-01 | 粘贴 RSS feed | 显示封面、节目列表（日期/时长/大小） |
| POD-02 | 粘贴 Atom feed | 同上 |
| POD-03 | feed 无封面 / 封面 404 | 使用占位图，不崩溃 |
| POD-04 | 单集下载 | 完成可播放，封面持久化到片库 |
| POD-05 | 订阅 → 出现在播客 Tab | 最新一期可一键下载 |
| POD-06 | 自动下载 1 / 3 / 5 | 刷新时按设置下载最新 N 期，去重 |
| POD-07 | 订阅 100+ 期的 feed | 只缓存最近 100 期，不无限增长 |
| POD-08 | OPML 导出 → 分享 | 文件合法（可被其他播客 App 导入） |
| POD-09 | OPML 导入（含无效行/重复项） | 去重导入，无效行跳过不崩 |
| POD-10 | feed 请求带 Referer=feedURL | 防盗链 feed 也能下载 |
| POD-11 | feed 解析失败（HTML 而非 XML） | 友好报错 |
| POD-12 | 取消订阅 | 已下载内容保留，列表不再刷新 |
| POD-13 | Pro 关闭时自动下载设置 | 自动下载被门控为 0，UI 提示需 Pro |

### 3.5 播放 / 字幕 / PiP / 后台音频（`PLY`）

| ID | 步骤 | 预期 |
|---|---|---|
| PLY-01 | 本地视频播放 | 正常起播，进度条可拖动 |
| PLY-02 | 音频（无视频轨） | 显示「正在播放」卡片，隐藏「存相册」 |
| PLY-03 | 倍速 0.75/1/1.25/1.5/2 | 生效且重启后保持 |
| PLY-04 | 退出再进入 | 从上次位置续播（±2s） |
| PLY-05 | 播放到结尾 | 标记 Played，进度清除 |
| PLY-06 | 播放队列上一集/下一集/自动连播 | 切换正确，进度各自独立 |
| PLY-07 | 内嵌字幕轨切换 | 显示/隐藏正确，重启后保持选择 |
| PLY-08 | HLS 旁挂 WebVTT 字幕 | 可加载、时间轴对齐（含 CJK 换行） |
| PLY-09 | 画中画进入/退出/后台 | PiP 窗口内容正确，返回 App 无黑屏 |
| PLY-10 | 锁屏/耳机控制 | 播放、暂停、拖动、下一集均可用 |
| PLY-11 | 来电 / 闹钟打断 | 中断后恢复播放（或按系统策略暂停），不死锁 |
| PLY-12 | 后台音频 30 分钟 | 不中断、内存稳定、锁屏信息更新 |
| PLY-13 | 播放中删除当前文件 | 优雅停止并提示，不崩溃 |

### 3.6 片库 / Files / 相册（`LIB`）

| ID | 步骤 | 预期 |
|---|---|---|
| LIB-01 | 搜索（中/英/数字/emoji） | 实时过滤，无卡顿（配合 PERF-02） |
| LIB-02 | 排序：最新/最早/最大/标题 | 顺序正确，重启保持 |
| LIB-03 | 多选删除 1 / 全选 | 文件、缩略图、索引同步清理 |
| LIB-04 | 存储统计 | 与实际文件大小一致（±1%） |
| LIB-05 | Files → On My iPhone → FluxKit → Media | 可见、可播放、可 AirDrop |
| LIB-06 | 从 Files 导入 mp4/mov/mp3 | 导入成功、命名友好、可播放 |
| LIB-07 | 导入不支持的类型（.pdf/.zip） | 明确拒绝 |
| LIB-08 | 导入大文件（>500MB） | 有进度、不阻塞 UI、成功后可播放 |
| LIB-09 | 存相册 | 权限允许 → 保存成功；拒绝 → 引导去设置 |
| LIB-10 | 删除相册权限后再次保存 | 提示去设置，不崩溃 |
| LIB-11 | 片库 0 项空状态 | 有引导文案，无广告占位异常 |
| LIB-12 | 缩略图缺失/损坏 | 占位图，不崩溃 |

### 3.7 设置 / 语言 / 通知（`SET`）

| ID | 步骤 | 预期 |
|---|---|---|
| SET-01 | 并发 1→4 修改 | 立即影响队列，重启保持 |
| SET-02 | 仅 Wi-Fi 开关 | 行为随之改变 |
| SET-03 | 播客自动下载 Off/1/3/5 | 持久化且受 Pro 门控 |
| SET-04 | 通知开关首次开启 | 弹出系统权限；拒绝后开关回滚并说明 |
| SET-05 | 通知关闭 | 不再发本地通知 |
| SET-06 | 语言：跟随系统 / 中文 / 英文 | 立即切换；分享扩展也跟随（App Group 同步） |
| SET-07 | 深色模式 | 全部页面可读（含 Paywall、播放器） |
| SET-08 | 关于/版本号 | 与 Info.plist 一致 |
| SET-09 | 清空缓存/删除全部 | 二次确认，执行后统计归零 |

### 3.8 订阅 FluxKit Pro（`PRO`）

| ID | 步骤 | 预期 |
|---|---|---|
| PRO-01 | Paywall 打开（有网/无网） | 有网显示价格；无网显示可读错误，不空白 |
| PRO-02 | 购买月付（Sandbox） | 变 Pro；并发可到 4；播客自动下载可选 |
| PRO-03 | 购买年付 | 同上 |
| PRO-04 | 恢复购买（同账号） | 恢复为 Pro |
| PRO-05 | 恢复购买（无购买记录） | 提示无可恢复项 |
| PRO-06 | 取消订阅 | 到期前仍为 Pro |
| PRO-07 | 退款 | 事件后权益收回（需服务器通知生效） |
| PRO-08 | 换设备登录同账号 → 恢复 | Pro 跟随 |
| PRO-09 | Offring 缺失 / 商品未就绪 | Paywall 显示「No subscription packages…」，不崩溃 |
| PRO-10 | key 缺失 / 填错 | 显示「RevenueCat isn't configured…」，其余功能（免费）可用 |
| PRO-11 | Pro 到期瞬间（时间调整） | 门控回落为 1 并发 |
| PRO-12 | 免费用户点播客自动下载 | 引导升级，不静默失败 |

### 3.9 分享扩展 / URL scheme / App Group（`SHR`）

| ID | 步骤 | 预期 |
|---|---|---|
| SHR-01 | Safari 分享网页 | 扩展显示成功卡片，点击打开主 App 并填入 |
| SHR-02 | 分享纯文本（含链接） | 提取链接写入 inbox |
| SHR-03 | 分享不含链接的文本 | 失败卡片，有解释 |
| SHR-04 | 分享图片/文件（不支持的类型） | 明确提示不支持 |
| SHR-05 | 连续分享 5 次再打开 App | inbox 上限 20，不丢最新一条，无重复 |
| SHR-06 | 主 App 前台时分享 | 回前台立即消费 |
| SHR-07 | 主 App 未安装扩展容器异常 | 不崩溃，提示「请先打开 App 一次」 |
| SHR-08 | `fluxkit://` 外部唤起传恶意参数（`javascript:`、`file:`、超长） | 只接受 http(s)，其余拒绝 |
| SHR-09 | 扩展内存受限（约 120MB）下分享大页面 | 不因内存被系统杀掉（无 OOM 日志） |

### 3.10 持久化与迁移（`PST`）

| ID | 步骤 | 预期 |
|---|---|---|
| PST-01 | 写入片库 → 杀进程 → 重启 | 数据完整 |
| PST-02 | 索引文件被截断/写入乱码 | 隔离为 `.corrupt-<ts>.json`，提示恢复，不覆盖用户数据 |
| PST-03 | 索引由更高 `schemaVersion` 写入 | 拒绝保存并提示，不降级破坏 |
| PST-04 | 从旧版本路径迁移（`AppPathsMigrationTests` 场景） | 迁移成功，旧文件按策略保留/清理 |
| PST-05 | 磁盘满时保存 | 有错误提示，原数据不损坏 |
| PST-06 | 播放进度每 5s 落盘 + 退出落盘 | 不丢进度、不过度写盘（配合 PERF-06） |

### 3.11 站点解析器（`SITE`）

| ID | 步骤 | 预期 |
|---|---|---|
| SITE-01 | 好看 `haokan.baidu.com` 分享链接 | 解析出可下地址 |
| SITE-02 | 搜狐 `tv.sohu.com` | 同上 |
| SITE-03 | 百度 `mbd.baidu.com` | 同上 |
| SITE-04 | Reddit 视频帖 | 同上 |
| SITE-05 | 已知站点但无播放地址 | 抛错并给可读提示（不静默失败） |
| SITE-06 | 未知站点 | 回落到通用解析，不影响既有路径 |
| SITE-07 | 站点返回 HTML 结构变更/空 body | 不崩溃，明确报错 |

---

## 4. 组合用例（`CMB`）—— 必须覆盖的 20 条

单功能全绿不代表组合正确。以下组合按风险排序，逐条手工执行。

| ID | 组合 | 关注点 |
|---|---|---|
| CMB-01 | HLS 下载 + 暂停 + 杀进程 + 重启 + 继续 | 分片复用、状态机不重复 |
| CMB-02 | 4 并发下载 + 仅 Wi-Fi + 切蜂窝 + 回 Wi-Fi | 队列暂停/恢复不丢任务 |
| CMB-03 | 下载中删除同一条目（正在写文件） | 文件句柄/删除竞态 |
| CMB-04 | 下载完成瞬间切后台（通知 + 落盘） | 回调与 UI 更新顺序 |
| CMB-05 | 后台下载完成 + 用户在其他 App | 后台会话回调、通知 |
| CMB-06 | 播客自动下载 × 并发上限 × Pro 状态切换 | 门控与队列计算 |
| CMB-07 | 播放中 PiP + 后台音频 + 锁屏控制 + 下载进行 | 音频会话互不干扰 |
| CMB-08 | 播放中删除当前条目 | 会话失效处理 |
| CMB-09 | 分享扩展连续 5 次 + App 冷启动 | App Group 读写竞态 |
| CMB-10 | 导入大文件 + 同时下载 4 个 | 磁盘 IO 与内存峰值 |
| CMB-11 | 弱网 + HLS 分片超时 + 重试 + 部分成功 | 重试上限与坏文件判定 |
| CMB-12 | 断网开始下载 → 恢复网络 | 自动/手动恢复行为 |
| CMB-13 | 语言切换 + 正在播放 + 通知已开启 | 文案与状态不串 |
| CMB-14 | Paywall 打开 + 网络断开 + 恢复网络 | offerings 重试 |
| CMB-15 | 购买成功瞬间 App 被杀 → 重启 | entitlement 同步（customerInfoStream） |
| CMB-16 | 片库 500 项 + 搜索 + 排序 + 多选删除 | 列表/索引性能与正确性 |
| CMB-17 | 磁盘接近满 + 下载 + 存相册 | 写失败处理 |
| CMB-18 | 系统时间/时区变更 + 订阅到期 | 门控判断 |
| CMB-19 | 低电量模式 + 后台下载/播放 | 系统限流下的行为 |
| CMB-20 | 网络权限被关闭（蜂窝数据禁用）+ 蜂窝环境 | 明确提示，不无限重试 |

---

## 5. 边界 / 异常 / 恶意输入（`EDG`）

| ID | 输入 | 预期 |
|---|---|---|
| EDG-01 | 空字符串 / 纯空格 / 纯 emoji | 提示无效，不发请求 |
| EDG-02 | 10 万字符粘贴文本 | 不卡死（<500ms），只取第一条链接 |
| EDG-03 | `http://` 明文地址（ATS 已放行） | 正常下载 |
| EDG-04 | 非 http(s) scheme（`javascript:`、`data:`、`intent:`） | 拒绝 |
| EDG-05 | 指向内网地址（`http://127.0.0.1`、`http://10.0.0.1`） | 允许或明确拒绝（记录当前策略，防止 SSRF 类误用） |
| EDG-06 | 服务器返回 `Content-Type: text/html` 但扩展名 .mp4 | 判定为页面而非媒体，提示 |
| EDG-07 | 服务器不支持 Range | 断点续传降级为整体重下，不卡死 |
| EDG-08 | 服务器 Content-Length 缺失 | 进度显示为不确定态，不崩 |
| EDG-09 | 极慢服务器（1KB/s） | 超时/取消可用，不无限挂起 |
| EDG-10 | m3u8 语法畸形（缺 `#EXTM3U`、分片数 0） | 明确报错 |
| EDG-11 | 恶意大 playlist（10 万行） | 不 OOM，解析耗时可控 |
| EDG-12 | 超长文件名（>255 字节）/ 保留名（`CON`、`.`） | 自动截断/重命名 |
| EDG-13 | 缩略图源损坏 | 占位图，不崩 |
| EDG-14 | 播放文件被截断 | 播放器报错，不崩溃 |
| EDG-15 | 系统时钟回拨/前进 | 进度、排序、订阅判断不异常 |

---

## 6. 性能测试（`PERF`）

**方法**：Xcode Instruments + XCTest 性能度量；每项跑 3 次取中位数；对比机型为 iPhone 12 及以上真机。

| ID | 指标 | 目标（P0 门禁） | 方法 |
|---|---|---|---|
| PERF-01 | 冷启动到首页可交互 | ≤1.5s；热启动 ≤0.6s | XCTest `XCTApplicationLaunchMetric` + Instruments App Launch |
| PERF-02 | 片库 500 项搜索输入响应 | 每次按键 ≤100ms，无 >250ms 主线程阻塞 | Time Profiler（Main Thread） |
| PERF-03 | 片库滚动流畅度 | hitch ratio < 5ms/s，掉帧 <1% | Animation Hitches |
| PERF-04 | HLS 下载内存峰值（6 并行分片） | <350MB | Allocations（Live Bytes） |
| PERF-05 | 直链 1GB 下载内存峰值 | <250MB（应流式写盘） | Allocations |
| PERF-06 | 索引写入（500 条） | <80ms，且不在主线程做整文件同步写 | Time Profiler |
| PERF-07 | 缩略图生成（1080p） | <300ms/条，批量时不阻塞 UI | signpost + Time Profiler |
| PERF-08 | 本地播放起播 | ≤800ms | Instruments + 埋点 |
| PERF-09 | 播客 feed 解析（100 期） | <300ms，后台线程 | Time Profiler |
| PERF-10 | 30 分钟后台音频耗电 | ≤4% | Energy Log |
| PERF-11 | 10 分钟 HLS 下载耗电 | ≤8% | Energy Log |
| PERF-12 | 包体积 | ≤30MB（App Store 下载大小） | Organizer / ASC |
| PERF-13 | HLS 吞吐 | ≥ 带宽 70%（6 并行） | 计时对比 |
| PERF-14 | 峰值并发任务 4 时 CPU | 平均 <60%，不触发温控降频 | Time Profiler + 温度观察 |

建议补的自动化性能测试（加到 `Tests/`）：

```swift
func testSearch500ItemsPerformance() {
    let records = (0..<500).map { makeRecord(title: "clip \($0)") }
    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
        _ = LibrarySearch.filter(records, query: "clip 42")
    }
}

func testLaunchPerformance() {
    measure(metrics: [XCTApplicationLaunchMetric()]) { XCUIApplication().launch() }
}
```

---

## 7. 稳定性 / 崩溃 / 死机（`STA`）

| ID | 场景 | 方法 | 判据 |
|---|---|---|---|
| STA-01 | 8 小时 soak：每 3 分钟下一条 5s 视频并删除 | 脚本 + `simctl`/真机 | 0 崩溃、内存无单调增长（<10% 漂移） |
| STA-02 | 500 条片库 + 连续 200 次搜索/排序 | 手工/XCUITest 循环 | 无 OOM、无卡顿累积 |
| STA-03 | 磁盘满（真机塞满）+ 下载 + 存相册 | 真机 | 有失败提示，不崩溃、不损坏索引 |
| STA-04 | 低内存（Xcode Simulate Memory Warning / 后台开大 App） | 真机+模拟器 | 无崩溃，可恢复 |
| STA-05 | 主线程阻塞扫描：所有页面空转 3 分钟 | Instruments Time Profiler | 无 >250ms 主线程任务；无 watchdog（20s）风险 |
| STA-06 | 冷启动 20 次（含杀进程） | 循环 | 无启动崩溃、无白屏 |
| STA-07 | 断点续传 50 次循环（暂停/继续） | 手工 | 无泄漏文件、无状态错乱 |
| STA-08 | 后台被杀（系统回收）+ 后台下载完成 | 真机 | 重启后能对齐完成状态 |
| STA-09 | 升级安装（旧版本→新版本）覆盖安装 | TestFlight 旧版本 | 数据完整、无迁移崩溃 |
| STA-10 | 24–72 小时长挂（播放 + 下载 + 分享） | 真机 | 无崩溃日志（Settings → Analytics Data） |

崩溃收集：Xcode → Window → Organizer → **Crashes**；真机 Settings → Privacy → Analytics → Analytics Data 搜 `FluxKit`。
建议后续接入 **MetricKit**（目前未接入）用于线上 hang/crash 指标。

---

## 8. 线程安全与并发（`THR`）—— 本项目的重点

代码里已有大量跨隔离边界的跳转，是竞态高发区。先跑工具，再做定向压测。

### 8.1 工具

```bash
DEST='platform=iOS Simulator,name=iPhone 18 Pro Max'

# 1) Thread Sanitizer（数据竞争）
xcodebuild test -project FluxKit.xcodeproj -scheme FluxKit -destination "$DEST" \
  -only-testing:FluxKitTests -enableThreadSanitizer YES

# 2) Address Sanitizer（越界/UAF/泄漏前置）
xcodebuild test -project FluxKit.xcodeproj -scheme FluxKit -destination "$DEST" \
  -only-testing:FluxKitTests -enableAddressSanitizer YES

# 3) Undefined Behavior Sanitizer
xcodebuild test -project FluxKit.xcodeproj -scheme FluxKit -destination "$DEST" \
  -only-testing:FluxKitTests -enableUndefinedBehaviorSanitizer YES

# 4) UI 测试 + TSan（更慢，但能覆盖视图层竞态）
xcodebuild test -project FluxKit.xcodeproj -scheme FluxKit -destination "$DEST" \
  -only-testing:FluxKitUITests -enableThreadSanitizer YES

# 5) Swift 严格并发检查（编译期预警，不改行为）
xcodebuild build -project FluxKit.xcodeproj -scheme FluxKit -sdk iphonesimulator \
  SWIFT_STRICT_CONCURRENCY=complete CODE_SIGNING_ALLOWED=NO

# 6) 泄漏：Instruments Leaks，挂到真机进程 10 分钟
xcrun xctrace record --template 'Leaks' --device <UDID> \
  --launch cloud.fluxkit.app --time-limit 10m --output leaks.trace
```

**门禁**：TSan 在单元测试 + 关键 UI 流程中 **0 报告**；Leaks 0 增长；严格并发检查的告警需逐条解释（允许存在但必须记录原因）。

### 8.2 定向怀疑点与复现

| ID | 位置 | 风险 | 复现步骤 | 期望不变量 |
|---|---|---|---|---|
| THR-01 | `DownloadManager.swift:721-846`（`nonisolated` 的 URLSession 回调 → `Task { @MainActor }`） | 回调顺序/重复投递、App 重连时重复状态更新 | 后台下载中杀进程重启，反复 20 次 | 记录状态单调推进；不出现「完成后又变下载中」 |
| THR-02 | `DownloadManager.swift:899` `TaskRegistry`（`@unchecked Sendable` + `NSLock`） | 旧任务回调覆盖新任务 | 地址过期→自动刷新→旧 task 回调到达（可用 403 场景构造） | 旧 task 回调被丢弃（已有单测，需端到端验证） |
| THR-03 | `DownloadManager.swift:880` `ProgressRelay`（`@unchecked Sendable`） | 进度乱序导致进度条回跳 | 4 并发 + 弱网 | 进度不倒退 |
| THR-04 | `BackgroundSessionBridge.swift:8` 静态锁 + completion handler | handler 被调用两次/丢失 → 系统断言或后台任务挂死 | 下载完成瞬间切后台、杀进程、再重启 | handler 恰好调用一次；后台任务不残留 |
| THR-05 | `Shared/SharedInbox.swift`（App Group `UserDefaults` 读改写） | 扩展 push 与 App pop 并发 → 丢链接 | 连续分享 5 次同时快速冷启动 App | 不丢最新一条；不重复消费 |
| THR-06 | `PersistedIndex`（整文件 JSON 写） | 并发保存导致半写/互相覆盖 | 下载完成 + 删除 + 播放进度同时落盘 | 文件始终能被解析；最坏丢失最后一次写入 |
| THR-07 | `PodcastStore.swift:160`（解析移出主线程）+ `FeedParser.swift:68` `Task.detached` | 捕获 MainActor 对象/状态回写竞争 | 快速切换订阅并刷新 | 无崩溃；列表最终一致 |
| THR-08 | `PiPManager.swift:50-70`（`nonisolated` 回调 → MainActor） | PiP 控制器在非主线程使用 | PiP 中锁屏/来电/旋转（不支持旋转但系统可能触发） | 无 AVKit 主线程断言崩溃 |
| THR-09 | `HLSDownloader.swift`（6 路分片）+ `:632` `SendableExportSession`（`@unchecked`） | 共享计数/文件写冲突、导出会话并发使用 | 大 HLS 下载中暂停/继续/删除 | 无重复写、无坏文件 |
| THR-10 | `LibraryStore` / `PodcastStore`（`@MainActor`，但做磁盘 IO） | 大目录下主线程卡顿 → watchdog 风险 | 500 条片库冷启动 + 进入片库 | 主线程单次阻塞 <250ms |

### 8.3 并发压测脚本（手工可执行）

```bash
# 并发下载 4 条 + 反复暂停/继续（用 smoke harness 起多条）
SIMCTL_CHILD_SMOKE_URLS="url1,url2,url3,url4" \
  xcrun simctl launch booted cloud.fluxkit.app --smoke-test
# 同时用 XCUITest 循环点「暂停/继续/删除」，观察 TSan/崩溃
```

---

## 9. 网络条件（`NET`）

用 Network Link Conditioner（真机：设置 → 开发者 → NLC；模拟器用 macOS 版）配置：

| ID | 配置 | 关注 |
|---|---|---|
| NET-01 | 100% 丢包 / 无网络 | 快速失败 + 可重试，不无限重试 |
| NET-02 | 1000ms 延迟 + 1% 丢包 | 进度、超时、重试正常 |
| NET-03 | 3G 低带宽（400kbps） | HLS 码率选择合理；不误判失败 |
| NET-04 | Wi-Fi ↔ 蜂窝切换（下载中） | 续传或明确失败；不崩溃 |
| NET-05 | DNS 失败 / 慢 DNS | 超时提示合理 |
| NET-06 | 服务器返回 500/502/503 | 重试退避；不无限重试 |
| NET-07 | CDN 中途断流（socket reset） | 可续传（直链）/分片重试（HLS） |
| NET-08 | 首次请求成功但分片域不可达（HLS） | 明确提示，不产出坏文件 |

---

## 10. 系统事件与生命周期（`SYS`）

| ID | 事件 | 期望 |
|---|---|---|
| SYS-01 | 来电 / 视频通话（播放中、下载中） | 音频中断正确处理，下载不崩 |
| SYS-02 | 低电量模式 | 不崩溃；行为符合系统策略 |
| SYS-03 | 屏幕锁定 / 解锁 | 后台音频与下载不受影响 |
| SYS-04 | 系统内存警告 | 释放缓存，不崩溃 |
| SYS-05 | 系统语言/时区变更 | 重启后文案与时间正确 |
| SYS-06 | 设备重启 + 后台下载完成 | 重新进入 App 后状态对齐 |
| SYS-07 | 存储权限/相册权限变更 | 操作时给出引导 |
| SYS-08 | App 被系统回收（前台长时间挂起） | 冷启动恢复可用 |

---

## 11. 兼容性 / 无障碍 / 本地化（`CMP`）

| ID | 项 | 期望 |
|---|---|---|
| CMP-01 | iOS 17.0 / 17.5 / 18.x / 最新 | 无崩溃，功能一致 |
| CMP-02 | iPhone SE（4.7"）/ 标准 / Pro Max | 布局不截断，按钮可点 |
| CMP-03 | 深色模式（唯一外观） | 全部页面对比度可读 |
| CMP-04 | 动态字体（最大辅助字号） | 关键按钮不被裁切（记录已知问题） |
| CMP-05 | VoiceOver | 主要流程可完成（首页/下载/播放/设置） |
| CMP-06 | 中/英切换 | 全部文案本地化，无残留英文/中文 |
| CMP-07 | 长文案（德语式长词，用英文长句模拟） | 不截断关键信息 |
| CMP-08 | 仅 iPhone（iPad 以兼容模式运行） | 可安装、可用、布局不破 |
| CMP-09 | 后台播放 + 灵动岛/刘海区域 | 无遮挡 |
| CMP-10 | 耳机拔出/蓝牙切换 | 按系统策略暂停，不崩 |

---

## 12. 安全与隐私（`SEC`）

| ID | 项 | 期望 |
|---|---|---|
| SEC-01 | 抓包（Charles/Proxyman）观察请求 | 只访问用户提供的 URL + RevenueCat 域名；无第三方分析/广告 |
| SEC-02 | 日志输出 | Release 构建不打印 URL 之外的敏感信息，不打印收据/token |
| SEC-03 | App Group 容器 | 只存链接与语言偏好，不含敏感数据 |
| SEC-04 | URL scheme 输入 | 只接受 http(s)，不执行任意命令 |
| SEC-05 | PrivacyInfo 声明 | 与实际 API 使用一致（UserDefaults 必需理由） |
| SEC-06 | 无 IDFA / 无 ATT | 代码中无 `ASIdentifierManager`、无 `ATTrackingManager` |
| SEC-07 | 隐私政策一致性 | App 隐私标签（Purchase History + User ID）与政策文本一致 |
| SEC-08 | 明文 HTTP | 允许（用户可粘贴 http 链接）；在审核备注中说明原因 |

---

## 13. 执行顺序建议（4 个工作日）

| 天 | 内容 |
|---|---|
| D1 | 修好当前编译问题 → `make test-unit` / `make test-ui` → 冒烟 10 条 → IN / DL 全量 |
| D2 | HLS 全量（含加密/字幕/直播/续传）+ POD 全量 + PLY 全量 |
| D3 | LIB / SET / PRO（沙盒）+ SHR + PST + SITE → 组合用例 CMB-01..20 |
| D4 | PERF 全部 + STA-01/03/06/07 + TSan/ASan 全量 + NET/SYS/CMP/SEC + 回归 |

---

## 14. 发布门禁（Go / No-Go）

**必须全部满足才可提交审核：**

- [ ] 冒烟 SMK-01..10 全绿
- [ ] 无 P0 / P1 缺陷；P2 有明确规避说明
- [ ] `make test-unit`（77+ 条）与 `make test-ui`（6 条）全绿
- [ ] TSan 单元测试 0 报告；Leaks 10 分钟 0 增长
- [ ] PERF-01/02/04/05/10 达标（超阈值 >20% 视为不达标）
- [ ] STA-01 8 小时 soak 无崩溃、内存无泄漏
- [ ] 沙盒订阅 E2E：购买 / 恢复 / 取消 / 退款 四条通过
- [ ] 分享扩展端到端可用（SHR-01/05/06）
- [ ] HLS 加密 + 字幕 + 直播拒绝三条路径正确
- [ ] 隐私/支持 URL 可访问且内容与 App 一致
- [ ] Release 包无 DEBUG 代码路径（`DebugSeed`/`SmokeTest` 不生效）

---

## 15. 缺陷记录模板

```
ID:            BUG-<递增>
标题:          [模块] 一句话现象
严重级:        P0 崩溃/数据丢失 | P1 主流程阻断 | P2 次要功能异常 | P3 体验/文案
环境:          机型 / iOS / 构建号 / 网络 / Pro 状态
前置条件:
复现步骤:      1) ... 2) ... （必须 3 次可复现）
期望 / 实际:
复现率:        x/3
证据:          截图 / 录屏 / 控制台日志 / crash log / Instruments 片段
疑似原因:      （可选，指向文件:行）
```

---

## 附录：现有自动化 → 缺口映射

| 模块 | 已有自动化 | 缺口（建议补） |
|---|---|---|
| 链接提取/校验 | `LinkExtractionTests`、`LinkURL` | 10 万字符、超长 URL、`javascript:` 等恶意输入 |
| 解析 | `LinkResolverTests`、`SiteExtractorTests` | 真实网络端到端（用本地 fixture 服务器） |
| 下载状态机 | `DownloadManagerRefreshTests` | URLSession 回调序列、后台上线重连、删除竞态 |
| HLS | `AESFixture`（解密向量） | 分片并发、续传、remux 产物校验（ffprobe） |
| 播客 | `FeedParserTests`、`PodcastStoreTests` | OPML 往返、自动下载去重、100 期上限 |
| 持久化 | `PersistedIndexTests`、`AppPathsMigrationTests` | 并发保存、磁盘满、版本降级 |
| 订阅 | `ProEntitlementsTests` | StoreKit Test（`.storekit` 配置）覆盖购买/恢复/取消 |
| 播放 | `SubtitleTests` | 队列/续播状态机（原 `PlaybackQueueTests` 已在重构中删除，需重建） |
| UI | 6 条 XCUITest | 下载全流程、Paywall 购买失败、分享扩展、深色/大字号 |
| 非功能 | 无 | 启动/搜索/滚动性能、TSan/ASan、Leaks、soak |

---

## 附录 B：已落地的自动化（本次新增）

| 能力 | 文件 | 说明 |
|---|---|---|
| StoreKit 本地配置 | `Configuration.storekit` | 与 ASC/RevenueCat 一致的两个订阅商品（`cloud.fluxkit.pro.monthly` / `.yearly`）、同一订阅组、en_US + zh_CN 本地化；已挂到 `FluxKit` scheme（`storeKitConfiguration`） |
| 商品契约测试 | `Tests/StoreKitConfigurationTests.swift` | 4 条：ID 与配置一致、价格/周期/订阅组正确、购买后成为 current entitlement、未知 ID 不被解析 |
| 性能基线 | `Tests/PerformanceTests.swift` | PERF-02（500 项搜索 ~0.6ms / 过滤+排序 ~1.3ms）、PERF-06（500 条索引存取 ~3.4ms） |
| 启动性能 | `UITests/LaunchPerformanceTests.swift` | PERF-01，`XCTApplicationLaunchMetric(waitUntilResponsive: true)` |
| 查询逻辑可测化 | `Sources/Core/LibraryQuery.swift` | 把片库过滤/排序从视图里抽成纯函数（UI 侧可后续改用它，行为已对齐） |
| 夜间消毒器 CI | `.github/workflows/sanitizers.yml` | 每晚 TSan + ASan 跑全部单元测试，另有 Swift 6 严格并发编译（非阻塞） |

**实测结果（本机 iPhone 18 Pro Max 模拟器）**：单元测试 147 条全绿；TSan 下 147 条全绿、0 数据竞争报告；asan 任务已配置在 CI。
