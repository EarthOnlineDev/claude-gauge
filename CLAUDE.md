# ClaudeGauge — 项目开发规则（CLAUDE.md）

> 本文件是本项目的"宪法"，AI 在任何改动前必须先读并遵守。
> 本项目是**已发布的开源产品**，不是脚手架。遵循全局 `~/.claude/CLAUDE.md` 的**核心原则**（自我改进循环、Plan Before Execute、Security-First、Do-It-Yourself、不可变、小文件、Git、HANDOVER），但具体规范按本项目"**bash + python 脚本 + 静态落地页**"的真实形态裁剪——全局模板里关于 shadcn/Zod/数据库/设计 token/Vercel analytics 的 Web SaaS 规范**不适用**，不要套用。

---

## 项目概览

ClaudeGauge 是一个 **macOS 菜单栏小工具**，实时、状态感知地显示 Claude Code（Pro/Max 订阅）的额度用量（5 小时窗口 + 一周窗口），让用户不打开 `/usage` 就能瞄一眼额度。

- **形态**：3 个独立脚本（SwiftBar 插件 / LaunchAgent 刷新器 / 可选 statusLine 桥接）+ 一个单文件静态落地页。无框架、无构建步骤、无 npm。
- **状态**：已完成、已开源、已上线（post-MVP，维护/迭代阶段）。
- **必读文档**（改代码前先读）：
  - [`docs/HANDOVER.md`](docs/HANDOVER.md) — 交接入口：当前状态、组件清单、已知局限、Roadmap、验收清单。
  - [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — 三层架构逐行详解、扩展点、行号索引。
  - [`README.md`](README.md) / [`README.zh-CN.md`](README.zh-CN.md) — 对外说明（双语）。

---

## 不可逾越的产品红线（HIGHEST PRIORITY）

### 隐私 / 安全 —— 这是产品的核心承诺，也是硬约束，违反即破坏产品立身之本

- **只读账户用量，绝不读对话/代码**：数据只来自 `api.anthropic.com/api/oauth/usage`（与 CC `/usage` 同源）。**绝不打开 `~/.claude/projects/`、对话日志或任何代码文件**。这是与多数竞品（ccusage、刘海工具们都在翻对话算用量）最关键的差异，是首屏主卖点，不容侵蚀。
- **token 只发往 Anthropic 官方**：用量端点 + OAuth refresh 端点（`platform.claude.com/v1/oauth/token`），别无他处。**零第三方、零遥测、零自有服务器。**
- **绝不在日志/输出里打印 token**：读进变量即用，必要时只打印长度/尾 4 位。（本会话曾因调试 print 泄露过 token，已轮换作废——别再犯。）
- **写回 keychain 必须保护用户其余凭证**：续命写回 `Claude Code-credentials` 时，读出**完整 blob**，**只改 `claudeAiOauth` 的 accessToken/refreshToken/expiresAt 三字段**，完整保留 `mcpOAuth`（用户其它 MCP 服务器的 OAuth token）及其余字段，用 `security add-generic-password -U` 原地更新（保留 ACL，不把用户登出）。**改任何 keychain 写入逻辑前：先备份 blob，改后验证结构完整。**
- **卸载干净**：`uninstall.sh` 绝不动用户的 CC 凭证与数据。

### 对外文案红线 —— 措辞必须诚实，宁可不说也不夸大

- **不写"纯本地 / 完全离线"**：默认菜单栏模式要联网调 Anthropic 用量端点。只有**可选的 statusLine 桥接模式**才是纯本地（零网络零额度）——这点可作为加分项，但不能当默认卖点。
- **"零额度消耗"只在确实成立时说**：用量轮询本身零额度；OAuth refresh 续命也是纯鉴权调用、零额度（已不再用早期会计费的 `claude -p`）。这些为真才可宣称。
- **首屏定调**：主打「只读官方用量、绝不读你的对话/代码」+「免费、开源、零额度」。不主打"免费/开源"当唯一卖点（人人都有），不夸大。

---

## 非目标（刻意不做，请勿加回）

- **阈值通知 / 系统弹窗通知** —— 产品方明确不要。"需要关注"靠**菜单栏变色**（够用近黑 / 75% 橙 / 90% 红）+ **诚实陈旧变灰**传达，不弹 macOS 通知。落地页一度出现过该虚假声明，已撤除，勿再加回或实现。
- **任何读对话做用量统计、内置对话查看器/搜索** —— 与隐私红线直接冲突。

---

## 架构速览（细节见 ARCHITECTURE.md）

三层互不依赖，只通过 `~/.cache/claude-gauge/` 下的文件通信，任一层挂掉不拖垮其它：

| 层 | 文件 | 安装位置 | 职责 |
|---|---|---|---|
| 渲染 | `plugin/claude-gauge.15s.sh` | `~/.swiftbar/` | SwiftBar 插件，读 cache/live 画菜单栏，正常路径不碰网络 |
| 数据 | `refresher/claude-gauge-refresh.sh` | `~/.claude/` | LaunchAgent 自适应节流轮询用量、原子写 cache、零额度自愈续命 |
| 桥接(可选) | `bridge/claude-gauge-statusline.py` | `~/.claude/` | CC statusLine，把实时 rate_limits 写 live.json（纯本地、零额度） |

LaunchAgent plist 由 `install.sh` 内联生成（label `dev.earthonline.claude-gauge`）。

---

## 技术栈现实

- **运行时依赖仅**：系统自带 `python3` + `security`（钥匙串）+ `launchctl` + `defaults`；菜单栏宿主 SwiftBar（`brew install --cask swiftbar`，install.sh 会补装）。**无 `claude` CLI 依赖、无 node、无构建。**
- **落地页**：`site/index.html` 单文件，内联 CSS/JS，EN/中文 i18n（`<span class="en/zh">` + `html[data-lang]` 切换）。**无框架、无打包。**
- **测试现状**：**当前无自动化测试套件**。验收靠 `docs/HANDOVER.md` §7 的人工冒烟/各层单测/关键行为验收。新增逻辑请同步补一条对应验收步骤——这是本项目的"测试"形态，不要假装有 80% 覆盖率。

---

## 开发工作流（裁剪版）

1. **Plan Before Execute**：任何非平凡改动（改逻辑、加组件、改架构、动 keychain）先 `EnterPlanMode`。改单个 typo/样式值可跳过。
2. **改 keychain 写入逻辑**：先 `security find-generic-password -s "Claude Code-credentials" -w > 备份`，改后跑 `refresh` 钩子验证 token 轮换 + `mcpOAuth` 等结构保留 + 无弹窗。
3. **文档行号同步（本项目反复踩的坑）**：改了 `refresher/` 等脚本的**行数**，必须同步 `ARCHITECTURE.md` / `HANDOVER.md` 里所有 `xxx.sh:NN` 行号引用。改完 grep 一遍 `:NN` 引用核对真实行号。
4. **安装一致性**：组件改动要让 **repo 源 ↔ 已安装文件**两处一致（同步拷贝或重跑 `install.sh`）。交接前 `diff` 确认零差异。
5. **冒烟测试**：涉及菜单栏显示的改动，装上后肉眼确认菜单栏正常出数、下拉正常、变色/陈旧/刘海宽度符合预期。
6. **Conventional commits**：`feat/fix/refactor/docs/chore` 等。直接在 `main` 上提交可接受（小项目单人维护）；attribution 已由全局 settings 关闭。
7. **收尾更新 `HANDOVER.md`**：当前状态 / 本次完成 / 下一步 / 关键决策。

---

## 自我改进循环（MANDATORY）

用户纠正或表达不满时（说"错了"、重复自己、问"为什么没有…"、自己动手修你漏的）：**立即**把模式、哪里错了、以后的规则写进 [`tasks/lessons.md`](tasks/lessons.md)。session 开始先读 lessons。纠正本身就是触发器，不必等用户要求。

---

## 部署 / 发布

- **GitHub**：https://github.com/EarthOnlineDev/claude-gauge （PUBLIC，org `EarthOnlineDev`）。
- **落地页部署**：Vercel team `earthonlinedevs-projects`，项目 `claude-gauge`。部署：把 `site/index.html` + `site/vercel.json` 拷到部署目录后 `vercel --prod --yes`，再 `vercel alias set <url> claude-gauge.earthonline.site`。
- **域名**：`claude-gauge.earthonline.site`，DNS 在**阿里云**（CNAME `claude-gauge` → `cname.vercel-dns.com`），不在 Vercel。
- **Do-It-Yourself**：凡是 CLI/API 能操作的（vercel / gh / 阿里云），自己直接做，不让用户去 Dashboard 手点。

---

## 代码质量（适用部分）

- **不可变**：不就地改对象/数组，造新副本（续命写回就是先 deep-copy 整个 blob 再改副本）。
- **原子写**：所有写 `~/.cache/claude-gauge/*.json` 都先写临时文件再 `os.replace`，防读到半截。
- **失败降级不破坏**：所有异常路径都安全降级（续命失败 → 缓存变陈旧变灰；poll 失败 → 退出不写脏数据），**绝不在失败时破坏 keychain 或写出坏缓存**。
- **小文件、错误显式处理、不吞错**；脚本里非显然的逻辑才加注释，解释 WHY。
- **无硬编码 secret**：本项目不存任何 secret（token 来自用户钥匙串，运行时读取）。
