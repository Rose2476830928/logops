# 协作与权限方案（logops）

> 对象：6 人小组全体成员 + 组长（仓库所有者）
> 前提：仓库是 **public**：https://github.com/Rose2476830928/logops.git
> 权威：本文件管"谁能做什么、怎么接进来"；代码怎么写、怎么判定完成，见 `AGENTS.md`。

---

## 一、结论（先看这三行）

1. **不建 Organization**：仓库留在组长个人账号下，加 5 名 `Write` 协作者，`main` 开分支规则。4 周课程作业，组织层的收益抵不上设置成本。
2. **保持 public**：GitHub Free 下，**只有 public 仓库**才免费拥有分支保护 / rulesets / 密钥推送拦截 / 无限 Actions 分钟；private 仓库要 GitHub Pro 或 Team 才有，每人每月约 4 美元。
3. **一人一号，绝不共用账号**：commit 归属、review 记录、2FA 都按人算，共用账号会让"谁写的、谁审的"全部失真——这正是教师第 7.3 节"协作与工程"要问的。

---

## 二、账号类型

| # | 账号类型 | 数量 | 谁需要 | 免费 | 说明 |
|---|---|---|---|---|---|
| 1 | GitHub 个人账号 | 6 | 全体成员 | ✅ | 用学校邮箱或常用邮箱注册；**必须开 2FA**（GitHub 已强制所有贡献代码的账号启用） |
| 2 | 仓库所有者（组长账号） | 1 | 组长 | ✅ | 天然 Admin，唯一能改设置/加人/删仓库的账号 |
| 3 | 协作者席位（Collaborator） | 5 | 组员 | ✅ | 不是独立账号，是"把你的账号加进这个仓库"；public 仓库协作者数量不设上限 |
| 4 | GitHub Actions 机器人 | 0 | — | ✅ | 内置 `GITHUB_TOKEN`，不需要注册机器账号。**不要**为 CI 另建账号或塞个人 PAT |
| 5 | GitHub Organization | 0（暂不建） | — | ✅ | 好处：仓库不绑在个人账号上、可用 Team 批量授权。代价：迁移 + 重建权限。课程结束后再考虑 |
| 6 | Deploy Key / PAT | 0（暂不需要） | — | ✅ | 只有在"服务器自动拉取代码"时才用。当前阶段一律用 SSH key 或交互式登录，不落地长期令牌 |

> 教师/助教**不需要邀请**：public 仓库任何人可直接浏览、clone、看 PR。只有当需要他们**管理 issue 或评论审批**时才给 `Triage`。

---

## 三、访问方式

| 场景 | 方式 | 谁用 | 要点 |
|---|---|---|---|
| 改文档（README/docs） | GitHub 网页直接编辑 | 全体 | 网页编辑会自动开分支并提示"Propose changes"→ 直接生成 PR，不用本地环境 |
| Linux/Ubuntu 本地开发 | **SSH key** | 主力开发（脚本、容器） | `ssh-keygen -t ed25519` → 公钥贴到 Settings → SSH keys。之后 `git clone git@github.com:...` 免密 |
| Windows 本地开发 | GitHub Desktop 或 VS Code + Git Credential Manager | Windows 组员 | 首次 push 弹浏览器授权，凭据由 GCM 托管，不用手输 token |
| 命令行 HTTPS | Fine-grained PAT（仅 `Contents: Read and write`） | 备选 | **过期时间设 30 天**，只存在本机凭据管理器，绝不写进脚本/文档 |
| CI（shellcheck 等） | Actions 内置 token | 流水线 | 权限在 workflow 里用 `permissions:` 显式最小化 |
| 查看/展示 | 浏览器直接访问 | 教师、旁听 | public 免登录可读，无需任何授权 |

**认证的硬事实**：public 仓库 `clone` **不需要**任何认证；只有 `push` 才需要。所以"我能 clone"证明不了"我有写权限"——验收时别用 clone 成功当权限证据。

---

## 四、权限角色划分

GitHub 仓库级共 5 档，本项目只用 3 档：

| GitHub 角色 | 能做什么 | 本项目给谁 | 人数 |
|---|---|---|---|
| **Admin** | 改设置、加人、删仓库、改分支保护 | **仅组长** | 1 |
| **Maintain** | 管 issue/PR/分支，但改不了敏感设置 | **不给**（能力尴尬：能管别人 PR 却管不了仓库，容易误操作） | 0 |
| **Write** | 推分支、开 PR、合并已批准的 PR | 5 名组员 | 5 |
| **Triage** | 只能管 issue/PR，不能推代码 | 需要参与评审的助教（可选） | 0–1 |
| **Read** | 只读 | 不需要（public 天然只读） | 0 |

### 4.1 角色 → 课程分工的映射

| 课程角色（要求 5.2） | 负责模块 | GitHub 权限 | 额外职责 |
|---|---|---|---|
| 组长 / 架构 | 整体 | Admin | 唯一能改设置；所有 PR 的最终合并权；分支保护的开通者 |
| 脚本开发 A | M1、M5 | Write | 评审 `init.sh` / `deploy.sh` 相关 PR |
| 脚本开发 B | M2 | Write | 评审 `analyze.sh` 相关 PR（指标口径以他为权威） |
| 容器与镜像 | M3、M4 | Write | 评审 `Dockerfile` / `compose.yml` 相关 PR |
| 数据与巡检 | M5 | Write | 评审 `check.sh` / crontab / 告警阈值相关 PR |
| 测试与文档 | 全部 | Write | 验收清单执行；文档 PR 的默认评审人 |

### 4.2 `main` 分支保护（组长开，10 分钟）

Settings → Rules → Rulesets → New branch ruleset，Target `main`：

| 选项 | 设为 | 理由 |
|---|---|---|
| Restrict deletions | ✅ | 防手滑删 main |
| Block force pushes | ✅ | 防改写历史 |
| Require a pull request before merging | ✅ | 直推 main 一律拒绝 |
| └ Required approvals | **1** | 6 人组要 2 个会互相卡进度 |
| └ Dismiss stale approvals | ✅ | 改了代码旧批准作废 |
| Require status checks | 暂空 | 等 shellcheck CI 建好再挂，别一开始就把自己锁死 |
| Bypass list | **留空**（含 Admin 也不放行） | 组长能绕过 = 规则等于没有 |

> 课程要求第 1 周就要"init.sh 连跑两次幂等"，第 3 周要"一键起"。**规则不要定得比进度严**：第一周先用"PR + 1 批准"，第 3 周再挂 CI 必过。

---

## 五、成员登记表

邀请台账（状态取自 2026-11-23 仓库 Settings → Collaborators）：

| GitHub 账号 | 显示名 | 权限 | 邀请状态 | 课程角色 / 模块 |
|---|---|---|---|---|
| `Rose2476830928` | Rose | **Admin** | 仓库所有者 | 组长 / 架构（整体） |
| `pumpkin3157-dotcom` | lisyu | Write | ✅ 已接受 | 待填 |
| `Youth-winner` | Youth-winner | Write | ✅ 已接受 | 待填 |
| `RXa-rxa` | AAtaY | Write | ⏳ Pending | 待填 |
| `zhangyannacl` | zhangyannacl | Write | ⏳ Pending | 待填 |
| `zhuoweivei-cloud` | zhuoweivei-cloud | Write | ⏳ Pending | 待填 |

> `Pending` = 邀请已发出、对方**尚未点接受**，此时没有任何写权限，`git push` 会报 `Permission denied`。三个待接受的账号在对方接受前，视为"已占位、未生效"。

> 这张表**只放组内**（群文件/私聊），**不要提交进仓库**——学号和真实姓名在 public 仓库里等于公开。仓库 `README.md` 末尾的分工表按课程要求写"角色 + 模块"，姓名学号是否上网先确认课程口径。

---

## 六、组长开通步骤（一次做完）

1. **邀请协作者**：Settings → Collaborators → Add people → 输 GitHub 用户名或邮箱 → 选 **Write** → 发送。✅ 已完成（5 人，见第五节台账）。
2. **催对方接受**：列表里显示 `Pending invite` 就是**还没生效**，人没接受前等于没权限。这一步最常被漏掉。⏳ 当前 3 人待接受。
3. **开 `main` 规则**（见 4.2）。
4. **打开密钥推送拦截**：Settings → Code security → 确认 **Secret scanning** 与 **Push protection** 为 Enabled（public 仓库免费）。
5. （可选）**CODEOWNERS**：建 `.github/CODEOWNERS`，让 PR 自动找对人：

```gitconfig
# 模块 → 默认评审人（把用户名换成实际账号）
*                       @Rose2476830928
/init.sh                @<脚本开发A>
/deploy.sh              @<脚本开发A>
/analyze.sh             @<脚本开发B>
/Dockerfile             @<容器与镜像>
/compose.yml            @<容器与镜像>
/check.sh               @<数据与巡检>
/docs/                  @<测试与文档>
```

6. （可选）**PR 模板** `.github/pull_request_template.md`，把"改了什么 / 怎么验证 / 影响哪个模块"变成必填，省掉一半来回追问。

---

## 七、组员接入

具体命令（配身份 → SSH → clone → 自检清单）已独立成操作手册：**`docs/workflow.md` 第 2 节**，本节不再重复。

只留两条不可省的结论：

| 事项 | 要求 | 违反后果 |
|---|---|---|
| 提交身份 | `git config user.email` 用**各自常用邮箱** | 提交历史里看不出是谁写的，教师问"这个模块谁负责"时无法回答 |
| 换行符 | Windows 组员设 `git config --global core.autocrlf input` | `.sh` 被存成 CRLF，到 Ubuntu 上报 `bash\r: No such file` |

> 仓库当前**远程仍为空**（`git ls-remote origin` 无输出），组长需先 `git push -u origin main`，否则组员 clone 下来是空的。判断依据与处理见 `docs/workflow.md` 第 1 节。

---

## 八、协作规范

### 8.1 分支

| 分支 | 用途 | 谁能推 |
|---|---|---|
| `main` | 常绿，随时可演示 | 无人直推，只走 PR |
| `feat/m<编号>-<简述>` | 新功能，如 `feat/m2-analyze` | 对应负责人 |
| `fix/<简述>` | 修 bug | 任何人 |
| `docs/<简述>` | 文档 | 任何人 |

一人一分支，**生命周期 ≤ 3 天**；超过 3 天先合并一部分，不要养大分支（大分支必冲突）。

### 8.2 提交

- 格式：`<模块> <动词> <对象>`，例 `M2 实现 TOP N 统计`、`M4 修正 healthcheck 间隔`
- 一个提交只做一件事；不提交"顺手改的格式"
- 提交前跑 `shellcheck *.sh`，告警清零（课程参考资料 [4] 明确要求）

### 8.3 Pull Request

| 项 | 规则 |
|---|---|
| 标题 | 带模块前缀，如 `[M2] 增加按小时请求趋势` |
| 描述 | 必写三行：改了什么 / 用什么命令验证 / 有没有影响别人的文件 |
| 关联 | 正文写 `Closes #12`，合并即自动关 issue |
| 体积 | 单 PR ≤ 400 行改动；超了就拆 |
| 批准 | 至少 1 人，**不能自审**（自己的 PR 不能自己点 approve） |
| 合并 | Squash merge；合并后删源分支 |
| 谁合并 | **组长统一合并**（每个节点日批次处理）；组员不自点合并，只负责推到 `Waiting for review`。检查项见下发件 4.4，步骤见 4.5 |

### 8.4 评审分工

- 改哪个模块，就找那个模块的负责人评审（见 4.1）
- 跨模块（`deploy.sh`、`compose.yml` 涉及多个）由组长评审
- 评审只看三件事：**能不能跑、会不会影响别人、有没有撒谎的数字**。风格问题不阻塞合并

### 8.5 节奏

| 频率 | 动作 |
|---|---|
| 每天 | 开工前 `git checkout main && git pull`，再开自己分支 |
| 每周 | 对齐课程周检查点（第 1 周可跑、第 2 周算对、第 3 周一键起、第 4 周只打磨） |
| 合并前 | 把自己的分支 rebase 到最新 `main`，本地跑一遍再推 |

### 8.6 冲突与沟通

- 冲突谁的分支谁解决，**不要 force push 到共享分支**
- 技术决策写进 Issue / PR 评论（留痕），群聊只做通知——教师问"为什么这么定"时，能翻出当时的讨论
- 任务即 Issue：开 issue 用已定的 8 个标签（`m1-init` … `integration`）

---

## 九、红线（public 仓库，一票否决）

| 禁止 | 后果 |
|---|---|
| 提交 `.env`、真实密码、token、私钥 | 课程要求第 9 节：**一旦提交即视为不合格** |
| 提交 `data/logs/*.log`、`out/` 产物、>1MB 日志 | 仓库变脏、clone 变慢；已由 `.gitignore` 拦住 |
| 提交组员姓名 + 学号 | public 仓库等于公开个人信息 |
| `git push --force` 到 `main` 或他人分支 | 覆盖别人工作，不可恢复 |
| `docker compose down -v` | 删卷即删数据 |
| 报告/README 里填估算数字 | 现场核对误差不为 0 直接扣分 |

**泄露后的正确动作**：立刻**吊销/更换**那个密码（不是删文件、不是改写历史）——删了提交不等于秘密变回秘密。

---

## 十、需要你裁决的三件事

| # | 事项 | 选项 A | 选项 B | 影响 |
|---|---|---|---|---|
| 1 | 仓库归属 | 留在个人账号（推荐） | 建 Organization 迁移 | A 快；B 抗"组长账号出问题"，但要重建权限 |
| 2 | 分工表是否进仓库 | 只写"角色 + 模块" | 写全姓名 + 学号 | 课程 5.2 模板要求姓名学号；public 仓库会公开。建议 A + 纸质/邮件另交 |
| 3 | 是否挂 CI 门禁 | 第 3 周再挂 shellcheck | 第 1 周就挂 | 早挂能防烂脚本，但初期脚本骨架未定容易卡住自己 |

---

## 附：一页速查

```text
谁能直推 main       → 没有人（含组长）
谁能改仓库设置       → 只有组长
组员能做什么         → 推自己分支 + 开 PR + 合并被批准的自己 PR
评审找谁            → 模块负责人；跨模块找组长
认证方式            → SSH（Linux）/ GitHub Desktop（Windows）
邮箱用哪个          → 各自常用邮箱（不改别名）；commit 会公开作者信息，别在文件里写字号
提交前必做          → shellcheck 清零 + 确认 git config user.email 是自己
拉取提交的具体步骤   → docs/workflow.md
```
