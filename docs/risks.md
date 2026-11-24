# logops 开发风险台账

> 定位：**可复用的踩坑清单**。每条写清「触发场景 → 影响范围 → 规避方式 → 怎么验证」。
> 维护：谁踩到新坑就加一条，附上当时的命令与报错原文；解决了也不要删，改为在"状态"里标注。
> 与其他文档的分工：本文件管"会怎么坏"，`AGENTS.md` 管"什么算完成"，`docs/workflow.md` 管"命令怎么写"。

## 怎么用

- **开工前**扫一眼 A 类（环境），环境不对后面全是白工；
- **写脚本时**对照 B 类，这五条都是"看起来对、跑起来错"；
- **做容器时**对照 C 类，其中 R11 和 R12 是课程骨架里本身就埋着的坑；
- **每个节点验收**对照 D 类，防止流程性失分。

**最高频的三条**（按踩中概率排序）：R11 只读挂载导致 nginx 起不来、R6 gawk 扩展在验收机崩、R9 `.env` 被覆盖。

---

## A 环境类

| 编号 | 风险点 | 触发场景 | 影响范围 | 规避方式 / 验证 |
|---|---|---|---|---|
| R1 | docker 守护进程未运行 | 重启电脑后 Docker Desktop 未自启；WSL 里 `systemctl stop docker` | `init.sh`/`check.sh`/`deploy.sh` 全部失败，报 `Cannot connect to the Docker daemon`。**实测曾发生**：Desktop 已装但引擎未起 | `init.sh` 的 `check_deps` 显式检测并提示启动命令；验证：`docker info >/dev/null && echo ok` |
| R2 | 仓库放在 Windows 挂载盘 | 直接在 `/mnt/d/桌面/.../logops` 里跑容器 | `chmod` 静默失效、容器内非 root 写日志失败、bind mount 跨文件系统性能差。**验收项 10「数据持久化」可能假通过** | 开发副本放 `~/logops`（ext4）；`init.sh` 检测 `/mnt/[a-z]/` 前缀主动警告；验证：`df -T .` 首行应为 ext4 |
| R3 | PATH 混入 Windows 的 docker.exe | WSL interop 把 Windows PATH 追加进来（实测报 `Failed to translate 'E:\C++\...\bin'`） | `docker` 命令连到 Windows 引擎，卷路径被解释成 `D:\...`，挂载指向错误目录或直接失败 | `init.sh` 校验 `docker version --format '{{.Server.Os}}'` 必须是 `linux`；验证：`command -v docker` 应输出 `/usr/bin/docker` |
| R4 | conda base 自动激活干扰 cron | 交互 shell 提示符带 `(base)`，cron 不加载 conda | 交互能跑、cron 报 `command not found`；PATH 里 awk/sed 版本可能与交互不同 | 开发时 `conda deactivate`；cron 条目用绝对路径与全路径命令；验证：`env -i /bin/bash -c './check.sh'` 模拟 cron 环境 |
| R5 | 换行符变成 CRLF | Windows 编辑器（记事本类）另存 `.sh` | 报 `bash\r: No such file or directory`，shebang 失效。这是本项目最典型的假故障 | `.gitattributes` 强制 `*.sh` 为 LF；Windows 侧 `git config core.autocrlf input`；验证：`git ls-files --eol \| grep -c crlf` 应为 0 |
| R22 | Git Bash（Windows）下进程创建极慢 | 脚本里大量 `$(...)`、管道、`awk`/`sort`/`sed` 外部命令 | **耗时几乎与数据量无关**：10 万行 47 秒、8 行 64 秒（`sys` 时间 37–40 秒），全是 fork 开销；回归测试跑 5 分钟，会让人不愿执行 | 验证统一在 WSL 里跑（同样脚本快 20 倍以上）；`write_report` 的百分比与柱状图改用 bash 算术，单行少 34 次进程；验证：`time ./tests/run-tests.sh` |

## B Shell 脚本类

| 编号 | 风险点 | 触发场景 | 影响范围 | 规避方式 / 验证 |
|---|---|---|---|---|
| R6 | gawk 扩展语法在 mawk 下崩 | `analyze.sh` 用 `gensub()`、`asort()`、`match($0,re,arr)` 三参数版、正则 `\s` | 开发机（Ubuntu 25.10，gawk 5.3）正常，验收机（22.04 默认 mawk）语法错或**静默算错**。验收项 5「指标正确」直接扣分，且现场才发现 | 只用 POSIX awk（空白用 `[[:space:]]`）；`AWK="${AWK:-awk}"` 允许切实现；验证：`AWK=mawk ./analyze.sh ...` 与 gawk 结果逐项一致 |
| R7 | `pipefail` 下管道被截断返回 141 | 写 `tr -dc 'A-Za-z0-9' < /dev/urandom \| head -c 16` | `set -euo pipefail` 让整条管道返回 141，脚本静默退出且无明显报错，表现为「init 跑到一半没了」 | 改 `dd if=/dev/urandom bs=1024 count=1 \| tr -dc ... \| cut -c1-16`（`cut` 读完所有输入，不触发 SIGPIPE）；验证：加 `set -euo pipefail` 跑一次，`echo $?` 为 0 |
| R7b | 随机数据量不足以凑够字符数 | 沿用 `bs=64` 生成 16 位密码 | 64 字节经 `tr` 过滤后平均只有约 15 个字符（可打印字母数字约占 24%），**实测出现长度 12**，密码生成失败 | 输入量放大到 `bs=1024`（过滤后约 240 字符）；保留长度校验 `[[ ${#pw} -eq 16 ]]`，宁可报错也不生成短密码；验证：循环 20 次全部 16 位 |
| R8 | `[[ 条件 ]] && 命令` 作为函数最后一句 | 函数末尾写 `[[ -f x ]] && log ok` | 条件为假时函数返回 1，调用处被 `set -e` 直接终止。表现为「明明检查都过了，脚本却退出」 | 一律改成 `if ... then ... fi`；验证：`shellcheck` 的 SC2015，或把条件设假跑一次 |
| R9 | `.env` 被重复执行覆盖 | `init.sh` 没有存在性判断，或每次无条件重写密码 | 已有数据卷的密码与新 `.env` 不一致 → db 连不上；验收项 2「连跑两次不改 .env」失败 | 存在即整体跳过；模板新增字段时**只警告缺字段、不自动改**；验证：连跑两次后 `sha256sum .env` 不变 |
| R10 | 密码进入仓库 | 把真实密码写进 `.env.example`、脚本或镜像 | 课程第 9 节：**一旦提交即视为不合格**；public 仓库永久留痕，删文件也没用 | 模板只留 `DB_PASSWORD=` 空占位；`init.sh` 随机生成 + `chmod 600`；`.gitignore` 拦截；验证：`git diff --cached \| grep -i 'password='` 只应看到空值 |
| R20 | 可选命令不存在被 `pipefail` 传成 127 | 写 `sc=$(shellcheck --version \| awk ...)` 而该命令未安装 | `set -e` 下整条管道返回 127，脚本在"看起来成功了"的位置**静默退出**，后续步骤全部跳过。**本轮实测踩中**：`init.sh` 生成 `.env` 后直接 exit 127，环境报告没写出来 | 先用 `command -v` 判断再调用，或 `( cmd \|\| true ) \| ...` 兜底；验证：`bash -c 'set -euo pipefail; x=$(not_exist \| cat); echo $?'` 应看到非 0 并确认已被捕获 |
| R21 | `trap ... EXIT` 的清理函数覆盖退出码 | `cleanup() { rm -rf "$TMPD"; }` 配 `trap cleanup EXIT`，而 `rm` 因权限、路径策略或安全软件失败 | 脚本**明明成功却返回 1**：产物齐全、日志无错，测试却全线飘红，排查方向完全跑偏。**本轮实测**：`analyze.sh` 的 4 个用例因此假失败，真实原因是环境的 safe-delete 拦截了 `rm` | `cleanup` 末尾 `return 0`，`rm` 加 `\|\| true`；验证：故意让清理步骤失败（指向受限路径），`echo $?` 仍应为 0 |

## C 容器与编排类

| 编号 | 风险点 | 触发场景 | 影响范围 | 规避方式 / 验证 |
|---|---|---|---|---|
| R11 | 日志目录只读挂载 | 照抄课程骨架 `- ./data/logs:/var/log/nginx:ro` | nginx 无法 `open() access.log`，容器启动即退出，`compose ps` 显示 `Exited`。连带验收项 7/9/10 全挂 | 去掉 `:ro`；`init.sh` 把日志目录设为 777（取舍见 R14）；验证：`docker compose up -d` 后 `ps` 不是 `Exited` |
| R12 | 非 root 进程绑定 80 端口 | `USER nginx` + `conf` 里 `listen 80` | 容器启动报 `bind() to 0.0.0.0:80 failed (13: Permission denied)` | 容器内 `listen 8080`，compose 里 `${WEB_PORT}:8080`；验证：`docker logs` 无 permission denied，`exec whoami` 非 root |
| R13 | healthcheck 用的工具镜像里没有 | 用 `nginx:latest`（Debian 基础）配 `curl -f` 做健康检查 | 检查永远失败 → 一直 `unhealthy` → 验收项 9 失败，且 `deploy.sh` 的等待会超时回滚 | 选 `nginx:1.27-alpine`（自带 busybox `wget`）；验证：`docker exec <c> wget -qO- http://127.0.0.1:8080/` 有输出 |
| R14 | 卷的 uid 不匹配 | 容器内 nginx 为 uid 101，宿主 `data/logs` 属主是 1000 且目录 755 | 写日志 permission denied，容器反复重启；报错藏在 `docker logs` 里，容易误判成配置错误 | 三选一：777（简单）/ `chown 101:101`（干净）/ compose 指定 `user:`（可控）。报告里写明取舍；验证：`docker exec <c> sh -c 'echo x >> /var/log/nginx/t.log'` |
| R15 | `version:` 字段与新 flag | `compose.yml` 写 `version: "3.8"`；`deploy.sh` 用 `docker compose up --wait` | `version` 自 Compose V2 起废弃（告警，部分版本报错）；`--wait` 等新 flag 在验收机的旧 compose 上不存在 → 报 `unknown flag` | `compose.yml` 不写 `version`；等待 healthy 自己写轮询 + 超时，不依赖新 flag；验证：`docker compose config` 无 warning |

## D 协作流程类

| 编号 | 风险点 | 触发场景 | 影响范围 | 规避方式 / 验证 |
|---|---|---|---|---|
| R16 | 双副本不同步 | `/mnt/d/.../logops` 与 `~/logops` 两边都改 | 代码分叉，push 上去的不是验证过的那份；排查时两处现象不一致 | 只在一处开发（`~/logops`），Windows 侧那份只读文档；验证：`git -C ~/logops status -sb` 与远程一致 |
| R17 | 基线期组员无实质产出 | 组员只"看懂了"、没有自己的 commit | 课程 25 分「过程与协作」、验收第 14 项「组员应答」、7.3 提问「这个模块是谁写的」三处同时失分 | 每人 ≥2 个实质 commit + D7 交 `docs/module-notes/<模块>.md`；验证：`git shortlog -sn` 与 `git diff --stat` |
| R18 | 功能冻结失效 | D12 之后仍往 `main` 加功能 | 演示前引入未验证代码，D13–D14 没有修复窗口 | D12 打 `node-4` 标签，之后只接受 `fix/*`；验证：`git log --oneline node-4..main` 只应出现 `fix` 开头的提交 |
| R19 | 报告里的数字对不上脚本 | 手填指标、用旧日志的结果 | 验收现场随机抽指标核对，误差不为 0 直接扣分 | 每个数字写清「命令 + 输入文件 + 输出值」；验证：按报告里的命令重跑一次，结果一致 |

---

## 当前实现状态（2026-11-23）

| 项 | 状态 | 说明 |
|---|---|---|
| `init.sh` 语法与静态检查（R8/R20） | **已验证通过** | `bash -n` 通过；`shellcheck -x` 用 `koalaman/shellcheck:stable` 容器跑，0 告警 |
| `init.sh` 依赖检查（R1/R3） | 已实现、已验证 | Windows 侧 docker 可用（29.4.0 / linux）时完整跑通；daemon 未起时按 R1 提示 exit 1 |
| `init.sh` 幂等（R9） | **已验证通过** | 连跑两次均 exit 0，第二次输出「.env 已存在，跳过」，`.env` 的 sha256 两次一致：`d55d4a9a…6a08` |
| 随机密码（R7/R7b/R10） | **已验证通过** | 20 次压测全部 16 位；只打印长度不打印内容；首版 `bs=64` 实测出现 12 位，已改 `bs=1024` |
| 参数与退出码（R8） | **已验证通过** | `--help` → exit 0；未知参数 → 打印用法 + exit 2 |
| 运行期产物不入库（R10） | **已验证通过** | `.env`、`data/logs/init-report.txt` 均被 `git check-ignore` 命中 |
| `analyze.sh` 六类指标（R6） | **已验证通过** | 10 万行样例的 9 项指标与独立 awk 手算逐项一致，明细见下 |
| `analyze.sh` 边界（R7/R21） | **已验证通过** | `.gz` 与明文 summary 完全一致；空日志 exit 0 且计数为 0；坏行计入 `unparsed_lines` 且不污染统计 |
| `analyze.sh` 静态检查 | **已验证通过** | `shellcheck -x` 0 告警（`SC2016` 因 printf 格式串含 Markdown 反引号，已按文件级豁免并注明原因） |
| `tests/run-tests.sh` | **已验证通过** | 32 项断言全过；支持 `./tests/run-tests.sh m1\|m2` 分节跑 |
| `/mnt` 路径告警（R2） | 已实现、未触发 | case 分支已用 `/mnt/d/…`、`/home/…`、`/d/…` 三个样本验证匹配正确；真实触发需在 WSL 的 `/mnt/d` 下运行 |
| 缺字段提示（R9） | 已实现、未验证 | 需要人工从 `.env` 删掉一行才能测，留给 WSL 环境补测 |
| R11–R15 | 尚未涉及 | 属 D4–D6 的实现范围，实现时逐条对照本表 |

### M2 零误差验证明细（2026-11-24）

数据：`data/logs/access-sample.log`，100000 行，Python `seed=20261124` 生成（不入库）。
"手算"指独立命令：`wc -l`、`awk '{print $1}' | sort -u | wc -l`、`awk '$9 ~ /^5[0-9][0-9]$/' | wc -l` 等。

| 指标 | 独立命令 | analyze.sh | 结果 |
|---|---|---|---|
| 总请求数 | 100000 | 100000 | 一致 |
| 独立 IP | 500 | 500 | 一致 |
| 2xx | 89946 | 89946 | 一致 |
| 3xx | 2911 | 2911 | 一致 |
| 4xx | 5054 | 5054 | 一致 |
| 5xx | 2089 | 2089 | 一致 |
| TOP1 URL | `/article/37` | `/article/37` | 一致 |
| TOP1 次数 | 2235 | 2235 | 一致 |
| 峰值小时 | 10（4267 次） | 10（4267 次） | 一致 |

