# 仓库访问与提交流程（logops）

> 定位：**操作手册**——每天怎么拉、怎么提、卡住怎么办。
> 配套：谁能做什么（权限/角色）见 `docs/collaboration.md`；什么算完成、什么算失败见 `AGENTS.md`。
> 仓库：https://github.com/Rose2476830928/logops.git （public）

---

## 0. 一分钟速览

```text
接受邀请 → 配身份 → 配 SSH → clone → 开分支 → 改 → 自检 → 精确 add → commit → push → PR → 合并 → 同步
```

| 你现在的状态 | 只看这几节 |
|---|---|
| 刚被邀请，什么都没装 | 第 2 节（首次配置） |
| 已经 clone 过，要开始干活 | 第 3、4 节（拉取 / 提交） |
| 要合并代码给别人用 | 第 5 节（PR 与合并） |
| 报错了 | 第 7 节（报错对照表） |
| 写代码前 | 第 8 节（开发注意事项） |

---

## 1. 开工前必须知道的现状

**远程仓库已有 `main` 分支。** 组长于 2026-11-24 完成首次 push（`c0d6b6a`，共 6 个提交）。

任何人用这条命令确认"仓库有东西了"：

```bash
git ls-remote origin        # 必须看到 refs/heads/main 才算通
```

> **历史教训（仍然有用）**：首次 push 之前，远程 `size=0`、`pushed_at` 等于创建时间，clone 只会得到「空仓库 + 一条 warning」。如果现在看到 `warning: You appear to have cloned an empty repository`，**不是"仓库还没建好"，而是 remote 地址写错或权限不足**——先 `git remote -v` 核对地址。
>
> 另一条：GitHub 已停用密码认证。若 `git push` 弹出 `Username for 'https://github.com'` 并要求密码，输什么都没用。本项目已把 remote 切到 SSH（`git@github.com:...`），组员 clone 用 https 也可以，但**推送一律用 SSH**。


---

## 2. 首次配置（每人只做一次，约 5 分钟）

### 2.1 接受邀请

登录 GitHub → 右上角铃铛 → 找到 `Rose2476830928 invited you to collaborate` → **Accept invitation**。

> 若仓库设置页仍显示 `Pending invite`，说明**还没点接受**，此时你没有任何写权限，`git push` 会报 `Permission denied`。这是最常见的"我明明被邀请了但推不上去"。

### 2.2 配提交身份（关键，别跳过）

```bash
git config --global user.name  "你的名字或昵称"
git config --global user.email "你的常用邮箱"
git config --global core.autocrlf input      # Windows 必设；Linux/macOS 无需
```

为什么要单独强调：`user.email` 决定 commit 上的作者信息。**没配的话 Git 会拿系统默认值**，提交历史里就会出现一串看不出是谁的提交，教师第 7.3 节问"这个模块是谁写的"时无法回答。

自检：

```bash
git config --global user.name; git config --global user.email
```

> 说明：仓库是 public，commit 里的作者名与邮箱会公开可见，这是既定选择，不需要额外处理；但**不要把学号、手机号写进任何文件或 commit message**。

### 2.3 配认证（SSH 推荐）

```bash
ssh-keygen -t ed25519 -C "你的邮箱"        # 一路回车即可，不必设密码
cat ~/.ssh/id_ed25519.pub                  # 复制整段输出
```

粘贴到 GitHub → Settings → **SSH and GPG keys** → New SSH key → 粘贴 → Add。

验证（必须看到 `Hi <你的用户名>!`）：

```bash
ssh -T git@github.com
```

Windows 组员若不想碰命令行：装 **GitHub Desktop** → File → Clone repository → 登录后选 `Rose2476830928/logops`。凭据由客户端托管，无需手输 token。

### 2.4 克隆

```bash
git clone git@github.com:Rose2476830928/logops.git      # SSH
# 或 https（Windows + GCM 可用）
git clone https://github.com/Rose2476830928/logops.git
cd logops
```

### 2.5 首次自检清单

| 检查 | 命令 | 期望 |
|---|---|---|
| 在仓库里 | `git rev-parse --show-toplevel` | 输出以 `/logops` 结尾 |
| 身份正确 | `git config user.email` | 是你的邮箱，不是别人的 |
| 远程正确 | `git remote -v` | 指向 `Rose2476830928/logops` |
| 能拉 | `git ls-remote origin` | 有 `refs/heads/main` |
| 能推（无副作用） | `git push --dry-run origin HEAD` | 不报 `Permission denied` |
| 工具齐 | `bash --version; docker --version; docker compose version; awk --version \| head -1` | 四项都有输出 |

`git push --dry-run` 是权限的**真实验证**——不做任何实际推送，只走一遍认证和授权检查。

---

## 3. 日常拉取（每次开工第一件事）

```bash
git switch main
git pull --ff-only
```

- 用 `--ff-only`：本地 `main` 不允许有自己造的合并提交，拉不下来就说明本地被污染了，应当立刻停手检查，而不是糊一个 merge 上去。
- **不要**在 `main` 上改代码。拉完立刻开新分支（见 4.1）。
- 一天之内第二次开工也要拉：别人可能已经合并了。

拉完确认自己在最新状态：

```bash
git log --oneline -3
git status -sb            # 期望：## main...origin/main（没有 ahead/behind）
```

---

## 4. 提交（完整流程）

### 4.1 开分支

```bash
git switch -c feat/m2-analyze        # 新功能：feat/m<模块号>-<简述>
git switch -c fix/check-exit-code    # 修 bug
git switch -c docs/collaboration     # 只改文档
```

一人一分支，**活不过 3 天**。超过就先合并一部分，不要养大分支——大分支合并必冲突，冲突必丢代码。

### 4.2 改，并在本地验证

推之前自己先跑一遍。验证不了的东西不要提 PR。

### 4.3 精确 add（最容易出事的一步）

```bash
git status                        # 先看清楚有什么
git add analyze.sh conf/nginx.conf # 只加你真正改的文件
git status                        # 再确认一遍暂存区
```

**禁止 `git add -A` / `git add .`**。它会顺手把 `.env`、`data/logs/*.log`、`qimo/` 之类一起塞进去。一旦 `.env` 进了提交，即使后面删掉，它也已经留在历史里了——处理方式只有"立刻更换那个密码"，不能靠删文件弥补。

提交前最后一道闸：

```bash
git status --short                # 暂存区里不该出现 .env / *.log / out/*
git diff --cached --stat          # 确认改的文件在你预期之内
```

### 4.4 commit

```bash
git commit -m "M2 实现 TOP N 统计"
```

格式：`<模块> <动词> <对象>`。示例：

| 好 | 差 | 为什么 |
|---|---|---|
| `M2 实现 TOP N 统计` | `update` | 看不出改了哪个模块、改了什么 |
| `M4 修正 healthcheck 间隔` | `fix bug` | 教师问"修了什么 bug"答不上来 |
| `docs 补充验收清单结果` | `1` | 无法检索 |

一个提交只做一件事。不要把"改了功能 + 顺手整理了格式"混在一个提交里——出问题时无法只回退其中一半。

### 4.5 push

```bash
git push -u origin HEAD
```

首次带 `-u`，之后同分支直接 `git push` 即可。

### 4.6 开 PR

推完 GitHub 会在页面上给一条 `Compare & pull request` 链接，点它。标题与描述见第 5 节。

---

## 5. PR 与合并

### 5.1 PR 描述必写三行

```markdown
## 改了什么
analyze.sh 增加按小时请求趋势，输出到 report.md 的第 6 节。

## 怎么验证
./analyze.sh --log data/logs/access.log --top 10 --out out
输出：report.md 第 6 节 24 行；手工核对 14 点这一行 = 1,203，一致。

## 影响
只改 analyze.sh，未动 compose.yml 与 Dockerfile。
```

第三行"影响"是给评审人看的：只改一个文件，评审 2 分钟能过；动了 `compose.yml`，全组都要重新起容器验证。

### 5.2 评审与合并规则

| 规则 | 内容 |
|---|---|
| 批准人数 | 至少 1 人，**不能自己批自己** |
| 找谁批 | 改哪个模块找那个模块负责人（见 `collaboration.md` 4.1）；跨模块找组长 |
| 合并方式 | **Squash and merge**（一个 PR 在 main 上只留一个干净提交） |
| 谁点合并 | **组长统一点**（每个节点日批次合并）；组员只负责推到 `Waiting for review`，不自点 |
| 合并前检查 | 组长按 12 项逐条核对（见下发件 4.4），任何一条不过就打回 |
| 合并后 | 删掉源分支；本地 `git switch main && git pull --ff-only && git branch -d <分支>` |

评审只看三件事：**能不能跑、会不会影响别人、有没有编造的数字**。代码风格不阻塞合并，别在缩进上纠结。

### 5.3 被保护的分支（实测规则，2026-11-24）

`main` 上的 ruleset 实际行为：

| 角色 | 能否直推 `main` | 说明 |
|---|---|---|
| 组员 | **不能** | 被拒，必须走 PR，且要有 1 名有写权限的人批准 |
| 组长（在 bypass list 里） | 能 | 但**优先也走 PR**，只在基线期赶进度或紧急修复时直推 |

组员直推时会看到：

```text
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
```

组长直推时会看到 `Bypassed rule violations`，这是 bypass 生效的正常提示，不是错误。

三个提醒：

1. **不要在网页上点「Update branch」以外的任何改写操作**，也别对 `main` 用 `--force`；
2. 组员的 PR 卡在 `Review required` 是**正常状态**，等组长批；不要自己去改仓库设置；
3. 组长**不能批准自己的 PR**（GitHub 硬限制），所以组长自己的改动要么直推（bypass），要么找一名组员批准——这也是让组员参与评审、留下真实 review 记录的机会，答辩时用得上。


---

## 6. 冲突处理

```bash
git switch main && git pull --ff-only
git switch feat/m2-analyze
git rebase main
```

冲突时 Git 会列出文件，每个冲突块形如：

```text
<<<<<<< HEAD
你的改动
=======
别人的改动
>>>>>>> main
```

处理原则：

1. **读懂两边在干什么**再删标记，不要凭感觉选一边；
2. 删掉 `<<<<<<<` / `=======` / `>>>>>>>` 三行标记；
3. `git add <冲突文件>` → `git rebase --continue`；
4. 拿不准就 `git rebase --abort` 退回原状，在群里问，**不要在冲突状态下继续改别的**。

**永远不要** `git push --force` 到 `main` 或别人的分支。force 会覆盖别人的提交，且无法通过 PR 恢复。

---

## 7. 报错对照表

| 现象 | 根因 | 处理 |
|---|---|---|
| `Permission denied (publickey)` | SSH key 没配或公钥没贴到 GitHub | `ssh -T git@github.com` 复测；重新贴公钥 |
| `remote: Permission to ... denied to <你>` | 邀请还是 `Pending`，没点接受 | 去 GitHub 点 Accept invitation |
| `warning: You appear to have cloned an empty repository` | 远程还没有任何提交 | 组长先 `git push -u origin main` |
| `bash\r: No such file or directory` | `.sh` 被存成了 CRLF | `dos2unix *.sh`；编辑器换行符改为 LF |
| `Updates were rejected (non-fast-forward)` | 远程有你没有的提交 | `git pull --rebase` 后再推 |
| `error: GH006: Protected branch update failed` | 在往 `main` 直推 | 开分支 + PR |
| `fatal: not a git repository` | 在错误目录执行 | `cd` 到仓库根，或 `git rev-parse --show-toplevel` 查 |
| `Your branch is behind ... by N commits` | 太久没拉 | `git pull --ff-only` |
| push 时要求输入密码且一直失败 | 用了 https 但没配 PAT | 换 SSH，或用 GitHub Desktop |
| `error: failed to push some refs` + 提示大文件 | 提交了日志/产物 | `git rm --cached <文件>`，检查 `.gitignore` |
| `.env` 已经提交上去了 | `git add -A` 且忽略规则没生效 | `git rm --cached .env` 后提交；**并立刻更换里面的密码** |

---

## 8. 开发注意事项

### 8.1 路径与执行环境

- 每个脚本第二行 `cd "$(dirname "$0")"`。cron 的工作目录不是仓库根，省了这行就会出现"手工跑正常、定时任务报找不到文件"。
- cron 里**一律写绝对路径**，并把输出重定向：`... >> data/logs/check.log 2>&1`。
- 不要依赖 `~` 或当前目录的隐式假设。

### 8.2 幂等（课程硬性要求 4.4③）

脚本必须能重复执行。第二次运行的正确表现是"已存在，跳过"并 exit 0，**不是**报错"目录已存在"。

```bash
mkdir -p data/logs out conf                      # -p 天然幂等
[[ -f .env ]] && log '.env 已存在，跳过' || cp .env.example .env
docker compose up -d                             # 天然幂等，不要用 docker run
```

### 8.3 密码与配置

- 密码、端口**只从 `.env` 读**，脚本里出现明文即视为不合格（课程第 9 节）。
- `.env` 由 `init.sh` 从 `.env.example` 生成，`.env` 永不入库。
- 报错信息里不要打印密码，`set -x` 调试完必须删掉。

### 8.4 日志与产物

- 日志写 `data/logs/`（容器挂卷到这里），产物写 `out/`。
- 这两处内容都不入库，只有 `.gitkeep` 入库。
- 需要给别人的样例日志放 `tests/fixtures/`，否则对方拿到仓库没有数据可跑。

### 8.5 脚本规范（课程 4.4④⑤）

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

usage() { echo "用法: $0 --log <文件> --top <N> --out <目录>"; }

# 参数缺失 → 打印用法 → exit 2
# 依赖缺失 → 明确报错 → exit 1
# 成功     → exit 0
```

- 所有变量加引号 `"$VAR"`；
- 临时文件用 `mktemp`，并用 `trap 'rm -f "$tmp"' EXIT` 清理；
- **不允许静默成功**：任何一步失败都要有可读的报错，且退出码非 0。

### 8.6 容器

- 容器内**非 root 运行**；`docker exec <容器> whoami` 必须不是 root。
- `healthcheck` 必须真的能反映服务可用性，`start_period` 给足，否则 `compose ps` 会显示 `Up (unhealthy)` 而你以为好了。
- **不要 `docker compose down -v`**：`-v` 会删卷，数据直接没了。演示时只用 `down`。

### 8.7 提交纪律

- 提交前跑 `shellcheck *.sh`，告警清零（课程参考资料 [4] 明确要求）。
- 不要把注释掉的旧代码、`TODO 待删`、调试 `echo` 留在提交里。
- 不要让 `main` 变红：PR 合并前必须本地跑通全流程。
- 报告、README 里的**每个数字都要能指到生成它的命令**。估算值、占位值、从别处抄来的数一律不行——验收现场会随机抽一条让教师核对。

### 8.8 需要停下来问的情况

- 要改别人负责的脚本；
- 要动 `.env.example` 的变量名（全组都会受影响）；
- 要改 `compose.yml` 的端口或卷；
- 冲突解决中拿不准哪边对；
- 想执行任何带 `-v`、`--force`、`reset --hard` 的命令。

---

## 9. 检查清单

### 每次提交前

- [ ] 在功能分支上，不在 `main`
- [ ] `git status --short` 里没有 `.env` / `*.log` / `out/` 内容
- [ ] `git diff --cached` 里只有我打算改的文件
- [ ] `shellcheck *.sh` 无告警
- [ ] 本地跑过一次，产物对得上
- [ ] commit 信息是 `<模块> <动词> <对象>`

### 每次合并前

- [ ] PR 描述有"改了什么 / 怎么验证 / 影响"
- [ ] 至少 1 人批准，且不是自己
- [ ] 分支已 rebase 到最新 `main`
- [ ] `Closes #<issue>` 已写

### 每周检查点（课程第六节）

- [ ] 第 1 周：`./init.sh` 连跑两次都成功，第二次输出"已存在，跳过"
- [ ] 第 2 周：`./analyze.sh` 指标与手工 `grep`/`awk` 误差为 0
- [ ] 第 3 周：`docker compose up -d` 全绿，停掉 web 后 `./check.sh` exit 1
- [ ] 第 4 周：`./deploy.sh` 从零到可访问 ≤ 10 分钟；不再加新功能
