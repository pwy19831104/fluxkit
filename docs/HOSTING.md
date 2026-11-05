# 官网 / 法务页托管方案（无需等备案）

> 目标：让下面三个 URL 在外网**稳定可访问**，因为 App 里的付费页链接和 Apple 的审核都依赖它们。
>
> - `https://<域名>/privacy-policy`
> - `https://<域名>/terms-of-service`
> - `https://<域名>/support`

## 为什么可以不等备案

备案约束的是**中国大陆境内的服务器 / CDN**。把这三页托管在境外（Cloudflare Pages 等）不需要备案；
域名解析仍留在阿里云也没问题——**只要不动 `@`（根域）的 A 记录**，正在进行的备案核验不受影响，
只新增一条子域 CNAME 即可。

## 页面从哪来

- 唯一来源：`docs/privacy-policy.md`、`docs/terms-of-use.md`、`docs/support.md`
- 生成：`make site`（等价于 `python3 scripts/build_site.py`，仅用系统 Python，无第三方依赖）
- 产物：`site/`（已提交到仓库，静态托管不需要构建步骤）

```
site/
├── index.html              → /
├── privacy-policy/index.html   → /privacy-policy
├── terms-of-service/index.html → /terms-of-service
├── support/index.html          → /support
├── 404.html
├── _redirects              → Cloudflare/Netlify 的 /terms、/faq 等旧链接 301
├── _headers                → 安全响应头与缓存策略
└── robots.txt
```

只用系统字体、无 JS、无外部请求（不拉 Google Fonts/CDN），因此在中国大陆访问也不会卡在别家的域名上。

---

# 方案 A（推荐）：Cloudflare Pages + 子域 `app.openkit.cloud`

**优点**：20 分钟上线、HTTPS 自动、免费、支持私有仓库、不动根域记录（备案安全）、push 即部署。
**代价**：URL 是 `app.openkit.cloud` 而不是 `openkit.cloud`（如果想用裸域，看方案 B）。

### 步骤

1. **注册/登录** [dash.cloudflare.com](https://dash.cloudflare.com)（免费计划即可）。
2. **Workers & Pages → Create → Pages → Connect to Git**，授权 GitHub，选择仓库
   `pwy19831104/fluxkit`（私有仓库也可以）。
3. **构建设置**填：

   | 字段 | 值 |
   |---|---|
   | Production branch | `main` |
   | Framework preset | `None` |
   | Build command | *（留空）* —— `site/` 已提交，无需构建 |
   | Build output directory | `site` |
   | Root directory | *（留空）* |

   > 想让 Cloudflare 每次用最新文档生成，也可以把 Build command 填
   > `python3 scripts/build_site.py`（Pages 的构建镜像自带 python3）。留空更稳。

4. 点 **Save and Deploy**，几十秒后得到 `https://<项目名>.pages.dev`。
5. **先验证**（这一步不涉及你的域名）：

   ```bash
   for p in / /privacy-policy /terms-of-service /support; do
     printf "%-18s" "$p"; curl -s -o /dev/null -w "%{http_code}\n" "https://<项目名>.pages.dev$p"
   done
   ```
   四个都要 `200`。

6. **绑定自定义域**：项目 → **Custom domains → Set up a custom domain →** 填 `app.openkit.cloud`。
7. **回阿里云云解析**加一条记录：

   | 记录类型 | 主机记录 | 记录值 | TTL |
   |---|---|---|---|
   | CNAME | `app` | `<项目名>.pages.dev` | 10 分钟（600） |

   不要改 `@` 和 `www` 的现有记录。
8. 等 1–5 分钟（证书签发 + 解析生效），验证：

   ```bash
   curl -I https://app.openkit.cloud/privacy-policy
   curl -I https://app.openkit.cloud/terms-of-service
   curl -I https://app.openkit.cloud/support
   ```
   HTTP/2 200，且证书有效（`curl` 不报 SSL 错误）。

9. **切换项目里的 URL**（仓库里 6 处）：

   ```bash
   cd fluxkit-ios
   grep -rl "https://openkit\.cloud" project.yml fastlane docs \
     | xargs sed -i '' 's#https://openkit\.cloud#https://app.openkit.cloud#g'
   xcodegen generate && make test-unit
   ```

   > 只会替换 `https://` 开头的地址，`support@openkit.cloud` 这类邮箱不受影响。

---

# 方案 B：备案通过后再用裸域 `openkit.cloud`

备案完成后，把根域也指向 Pages：

- Pages 项目 → Custom domains → 添加 `openkit.cloud` 与 `www.openkit.cloud`
- 阿里云解析：把 `@` 改成 CNAME 到 `<项目名>.pages.dev`（阿里云云解析支持根域 CNAME；若你同时用该域收发邮件，确认 MX 记录保留）

**如果计划走 B，就现在直接用方案 A 上线**，等备案下来再换域名——三个路径不变，App 只需在换域名后随下一个版本更新 URL（或干脆永久保留 `app.openkit.cloud`，省一次发版）。

---

# 方案 C：等备案，自己托管

备案通过后在现有阿里云主机上：

1. 把 `site/` 上传到站点根目录（`/privacy-policy/index.html` 等路径必须完全一致）。
2. 给域名申请免费 DV 证书，配置 443 监听并 `301` 跳转 http→https。
3. 修掉现在的问题：实测 `http://openkit.cloud` 返回 **403（Server: Beaver）**，
   `https://openkit.cloud` TLS 握手直接 EOF（无证书）——说明站点本身还没配好。

**风险**：备案 5–20 个工作日，这期间你无法提交审核（Apple 抓不到隐私政策 URL）。

---

# 方案 D：GitHub Pages

- 仓库是私有的 → Pages 需要 **GitHub Pro**；或者把仓库改成 public。
- 设置：Settings → Pages → Source `Deploy from a branch` → `main` / `/site`。
- 需要额外放一个 `site/CNAME` 文件写入域名。
- private repo 用 Pages 不划算，个人项目更推荐 A。

---

# 维护流程

```bash
# 改文案
$EDITOR docs/privacy-policy.md      # 或 terms-of-use.md / support.md
make site                            # 重新生成 site/
git add docs site && git commit -m "Update legal pages" && git push
# Cloudflare Pages 会自动部署（约 30 秒）
```

改完法律文本记得同步改 `**Last updated**` 日期。

---

# 上线前校验清单（照抄执行）

- [ ] `curl -I https://<域名>/{privacy-policy,terms-of-service,support}` 全部 `200`
- [ ] 手机 Safari **无痕模式**打开三个页面：无证书警告、无 403、不需要登录
- [ ] 页面里的 `/privacy-policy`、`/terms-of-service`、`support@openkit.cloud` 链接能点开
- [ ] 中文段落显示正常（`docs/support.md` 有中文 FAQ）
- [ ] 深色模式下可读（系统深色模式打开一次）
- [ ] `project.yml` 的 `SKPrivacyPolicyURL` / `SKTermsURL` 与 `fastlane/metadata/*/privacy_url.txt`、`support_url.txt` 指向同一域名
- [ ] 提交审核前，用[苹果的网络环境]再确认一次（境外可访问 ≠ 中国大陆可访问，App 用户可以任何地区，二审也会抓取）

---

# 常见问题

**Q：法务页放境外，会不会影响备案？**
A：不会。备案针对的是境内服务器主体，这三页属于境外托管；只要根域 A 记录仍指向备案的境内服务器，核验不受影响。

**Q：Cloudflare 免费额度够吗？**
A：免费计划每月 500 次构建、带宽不限，个人项目绰绰有余。

**Q：以后想加中文版法律文本？**
A：在 `docs/` 里加 `privacy-policy.zh.md`，然后在 `scripts/build_site.py` 的 `PAGES` 列表里加一条
（`("privacy-policy.zh.md", "privacy-policy/zh", …)`），`make site` 即可。
