# logops 实现说明与学习指引

> 给谁看：要改代码的组员、要答辩的全员。
> 怎么用：第 1 章看整体，第 2 章对照代码读，第 3 章防"改一处崩三处"，第 4 章按自己角色精读，第 5 章对着练答辩。
> 与其他文档的分工：本文讲**实现**，`AGENTS.md` 讲规约，`docs/risks.md` 讲坑，v2.0 方案讲流程。

## 1 整体实现方法

### 1.1 一句话架构

五个 Shell 脚本 + 一组容器，把"管理员手工 tail 日志、粘贴 Excel"变成"一条命令交付"。核心是一个**单向数据流**：日志进 → 指标出 → 静态页展示 → 定时巡检。

### 1.2 数据流

```
nginx 容器（非 root，监听 8080）
   │  access_log /var/log/nginx/access.log（combined 格式）
   ▼
data/logs/access.log        ← compose 卷挂载（必须可写，不能 :ro）
   │
   ├──► analyze.sh ──► out/report.md      六类指标的可读报告
   │                └► out/summary.csv    指标键值对，Excel 可开
   │                        │
   │                        ▼
   │                  nginx /report/  →  /usr/share/nginx/html/report（只读挂载）
   │
   └──► check.sh（cron 调用）──► data/logs/alert.log   阈值告警

deploy.sh：build → up → 等 healthy → 调 analyze.sh → 打印访问地址
```

### 1.3 五个关键设计决策

每个决策都有明确理由，答辩被问"为什么这么做"时按这张表答：

| # | 决策 | 理由 | 反面做法会怎样 |
|---|---|---|---|
| 1 | `analyze.sh` 只扫描文件 **2 遍**（`calc_core` + `calc_details`） | 六类指标各扫一遍是 6 倍 I/O；10 万行时差别明显 | 6 遍扫描，Java 化的 Shell |
| 2 | awk 只用 **POSIX 子集** | 验收机 Ubuntu 22.04 默认 mawk，`gensub`/`asort`/`\s` 会直接报错或静默算错 | 开发机（gawk）正常，验收机崩 |
| 3 | 容器 **非 root + 8080 端口** | 镜像里跑 root 是安全反模式；非 root 绑不了 1024 以下端口，所以必须改 8080 | 绑 80 会 `Permission denied`，容器起不来 |
| 4 | healthcheck 打 **`/healthz` 且关日志** | 探活每 10 秒一次，进日志就是一天 8640 条伪请求，访问量全虚高 | 统计失真，报告数字与真实业务不符 |
| 5 | 所有脚本 **幂等**（存在即跳过） | 要能被 cron 反复调用，第二次运行不能报错、不能覆盖配置 | 第二次跑就"目录已存在"失败，cron 天天报警 |

### 1.4 模块依赖

```
M1 init.sh ─┐
M2 analyze.sh ─┼─► M5 deploy.sh（串起 build → up → analyze）
M4 compose.yml ─┘
M3 Dockerfile ──► M4 compose.yml ──► M5 check.sh（只依赖服务名）
```

**M4 是关键路径**：`deploy.sh` 和 `check.sh` 都等它定下服务名与容器行为。

## 2 脚本逐个拆解

### 2.1 `init.sh`（161 行）

**职责**：把仓库从"刚 clone 的裸状态"变成"能跑的状态"。不碰容器，只做准备。

**执行顺序**（`main()` 第 145–159 行）：参数检查 → `check_platform` → `check_deps` → `make_dirs` → `ensure_env` → `write_report`。

| 函数 | 行号 | 做什么 | 为什么这么写 |
|---|---|---|---|
| `gen_pw` | 35–41 | 生成 16 位随机密码 | 用 `dd \| tr \| cut`，**不用 `tr \| head`**——`pipefail` 下 head 提前关闭管道会让整条命令返回 141，脚本直接退出 |
| `check_platform` | 43–51 | 检测仓库是否在 `/mnt/[a-z]/` 下 | Windows 挂载盘上 `chmod` 不生效、容器卷权限异常，提前警告比事后排查省两天 |
| `check_deps` | 53–66 | 7 个命令 + compose + daemon + `Server.Os` | 最后一条是防 PATH 命中 Windows 的 `docker.exe`，那会连到错的引擎 |
| `make_dirs` | 68–86 | 建 3 个目录 + `.gitkeep` + `chmod 777 data/logs` | 777 是为了让容器内非 root 的 nginx 能写日志（取舍见 risks R14） |
| `check_env_keys` | 88–100 | `.env` 存在时比对模板字段 | **只警告、不修改**——一旦自动补字段就破坏了"重复执行不改 .env" |
| `ensure_env` | 102–116 | 不存在才生成，`chmod 600` | 幂等的核心：`[[ -f "$ENV_FILE" ]]` 就跳过 |
| `write_report` | 126–143 | 写 `data/logs/init-report.txt` | 记录 bash/awk/docker/compose 版本，答辩时能证明"这个环境为什么能跑" |

**三个易错点**

1. `gen_pw` 的 `bs=1024` 不能改小：64 字节经 `tr` 过滤后平均只有 15 个字符，凑不够 16 位（实测出现过 12 位）。
2. `check_env_keys` 里 `grep -q "^${key}="` 不能改成 `sed` 去改文件——那就不是幂等了。
3. `docker compose version` 的报错文案要能指导动作（已写成 `sudo apt install docker-compose-v2`），比"不可用"有用得多。

### 2.2 `analyze.sh`（309 行）

**职责**：日志进，六类指标出。是整个项目唯一有算法的地方。

**输入契约**（nginx combined，字段位置固定）：

| 字段 | 含义 | 用途 |
|---|---|---|
| `$1` | 客户端 IP | 独立 IP 去重 |
| `$4` | `[24/Nov/2026:10:00:00` | 用 `split($4,t,":")` 取 `t[2]` 得到小时 |
| `$7` | 请求路径 | TOP N、5xx 明细 |
| `$9` | 状态码 | 状态分布、5xx 判定 |

**输出契约**：`out/report.md`（5 节可读表格）+ `out/summary.csv`（11 行 `metric,value`）。

**六个指标分别由哪段算出**：

| 指标 | 位置 | 实现要点 |
|---|---|---|
| 总请求数 | `calc_core` 第 93–95 行 | `NF == 0` 跳过空行，其余累加 `total` |
| 无法解析行 | 第 96 行 | 字段数 < 9 或 `$9` 不是三位数字 → `bad++` 且 `next`（不污染其他统计） |
| 独立 IP | 第 97、107–108 行 | `ips[$1] = 1` 用关联数组去重，`END` 里数键的个数 |
| 状态码分布 | `calc_details` 第 124 行 | `st[$9]++`，再按 code 分 `2/3/4/5` 四类汇总（第 98–102 行） |
| TOP N URL | 第 123 行 + 第 140–141 行 | `url[$7]++` 后 `sort -k1,1nr -k2,2` 取前 N |
| 5xx 明细 | 第 125 行 | 只在 `$9 ~ /^5[0-9][0-9]$/` 时 `e5[$7]++` |
| 按小时趋势 | 第 127–130 行 | `split($4,t,":")` 取 `t[2]`，且校验是两位数字 |
| 峰值小时 | `calc_core` 第 109–112 行 | 遍历 `hour[]` 取最大值 |

**三个值得讲的设计**

1. **`details.tsv` 的类型前缀**（第 131–136 行）：一次 awk 输出 `Q/S/E/H` 四类，之后用 `awk -F'\t' '$1=="Q"'` 分流。这样全文件只解析两次，而分流用 awk 不用 `grep`——因为 `grep` 无匹配时返回 1，`pipefail` 下会让脚本退出。
2. **确定性排序**（第 140–145 行）：`sort -k1,1nr -k2,2` 加了次级键按 URL 升序。否则同分时顺序取决于 awk 数组遍历顺序，而 **gawk 与 mawk 的遍历顺序不同**，同一份日志两次跑可能出不同结果。
3. **百分比与柱状图用 bash 算术**（`pct` 159–167、`bar` 169–182）：原来的写法每行表格 fork 一次 awk，一份报告 34 次进程；改纯 bash 后 Windows 上快了近十倍（虽然 Linux 上本来就快）。

**易错点**

- `cleanup`（45–51）末尾必须 `return 0`：`trap EXIT` 的返回值会覆盖脚本退出码，`rm` 失败会让"成功的运行"返回 1。
- 状态码判定用 `$9 !~ /^[0-9][0-9][0-9]$/` 而不是 `NF < 9` 一个条件，两者都要，否则字段够 9 个但状态码是 `-` 的行会算错。

### 2.3 `Dockerfile`（43 行）

| 行 | 指令 | 说明 |
|---|---|---|
| 11 | `FROM nginx:1.27-alpine` | alpine 自带 busybox `wget`（healthcheck 用）；Debian 版既没 curl 也没 wget |
| 16 | `COPY conf/nginx.conf` | 覆盖默认配置（非 root 必需的改动） |
| 19–25 | `RUN printf ... > index.html` | 首页给 healthcheck 一个稳定目标，也方便人工确认 |
| 30–31 | `chown -R nginx:nginx /var/cache/nginx /usr/share/nginx/html` | 构建时属主；**日志目录不行**，因为它是指向 `/dev/stdout` 的符号链接 |
| 33 | `USER nginx` | `docker exec whoami` 必须是 `nginx`（验收项 8） |
| 39–40 | `HEALTHCHECK ... wget /healthz` | 打专用路径，不污染访问日志 |

**非 root 的"三件套"**（缺一个就起不来）：`listen 8080` + `pid /tmp/nginx.pid` + 所有 `*_temp_path` 指 `/tmp`。原因见 `conf/nginx.conf` 顶部注释。

### 2.4 `conf/nginx.conf`（62 行）

| 行 | 配置 | 为什么 |
|---|---|---|
| 8 | `pid /tmp/nginx.pid` | `/var/run` 非 root 不可写 |
| 19–23 | 五个 `*_temp_path` → `/tmp` | `/var/cache/nginx` 非 root 不可写 |
| 26–28 | `log_format main`（combined 兼容） | **这是与 analyze.sh 的契约**：字段位置 `${1}/${4}/${7}/${9}` 必须对得上 |
| 36 | `listen 8080` | 非 root 不能绑 80 |
| 48–52 | `location = /healthz { access_log off; }` | 探活不进日志 |
| 55–59 | `location /report/ { alias ... }` | 让 `out/` 挂载后能在浏览器直接看报告 |

### 2.5 `tests/run-tests.sh`（215 行）

**结构**：断言函数（`ok`/`bad`/`skip`/`assert_eq`）→ M1 节 → M2 节 → M3 节 → 汇总。支持 `./tests/run-tests.sh m1|m2|m3` 分节跑。

**为什么不用 `set -e`**：单个用例失败要继续跑完，否则一次只能发现一个问题。

**docker 不可用时为什么 SKIP 而不是 FAIL**：M1/M3 依赖 docker，环境没起时不该算代码错。但注意 `docker info` 通过 **不代表** `docker compose` 可用——这两个是不同的检查。

**怎么加新用例**：复制一节的结构，写 `if want m4; then ... fi`，断言用 `assert_eq "描述" "期望" "$(实际)"`。

### 2.6 待开发的三个模块（M4/M5）

**`compose.yml`**（M4）——已知的四个硬约束：

| 约束 | 原因 |
|---|---|
| 日志卷**不能加 `:ro`** | `:ro` 下 nginx 无法写 access.log，容器启动即退出 |
| 必须挂载**整个 `/var/log/nginx` 目录** | 官方镜像里该文件是 `/dev/stdout` 的符号链接，不覆盖就永远不落盘 |
| **不写 `version:` 字段** | Compose V2 起废弃，v5 会告警 |
| 端口用 `${WEB_PORT}:8080` | 宿主端口来自 `.env`；容器内是 8080（非 root） |

**`check.sh`**（M5）——四类判定：磁盘 `df -P /`、内存 `free`、容器 `docker compose ps`、端口。阈值从 `.env` 读 `DISK_THRESHOLD`/`MEM_THRESHOLD`，异常 `exit 1` 并写 `data/logs/alert.log`。

**`deploy.sh`**（M5）——串 `docker compose build` → `up -d` → **轮询**等 healthy（带超时，**不用 `--wait`**，验收机的 compose 版本未必支持）→ 调 `analyze.sh` → 打印地址；任一步失败要回滚并给明确报错。

## 3 跨模块契约（改一处崩三处的地方）

| 契约 | 谁产出 | 谁消费 | 破了会怎样 |
|---|---|---|---|
| 日志字段位置 `$1/$4/$7/$9` | `conf/nginx.conf` 的 `log_format` | `analyze.sh` 的 awk | 指标全算错，且不报错 |
| `summary.csv` 的 11 个 metric 名 | `analyze.sh` 的 `write_csv` | 报告、看板、验收 | 下游取不到值 |
| `.env` 字段名 | `.env.example` | `init.sh`、`compose.yml`、`check.sh` | 变量为空，容器起不来或阈值失效 |
| 服务名 `WEB_SERVICE=web` | `.env.example` | `compose.yml`、`check.sh` | `check.sh` 找不到容器，永远报"未运行" |
| 容器内端口 8080 | `conf/nginx.conf` + `Dockerfile` | `compose.yml` 的端口映射 | 映射到不存在的端口，访问 502 |
| 产物路径 `out/report.md`、`out/summary.csv` | `analyze.sh` | `compose.yml` 挂载、README、验收 | 页面上空白，验收按名查找失败 |

## 4 各成员要熟悉什么

### 4.1 组长（整体）

**必须懂**：六条数据流为什么这样连；每个模块的验收命令；`GH013` 与 bypass 的边界。
**可以不懂**：mawk 与 gawk 的具体差异（知道"只用 POSIX 子集"即可）。
**答辩会问**：为什么先做基线而不是六人并行？→ 接口不打架、组员有东西可测、答辩讲得清改动。
**自测**：能在不看书的情况下画出 1.2 的数据流，并说清每个箭头的载体是什么。

### 4.2 脚本开发 A（M1 `init.sh` + M5 `deploy.sh`）

**必须懂**：
- `init.sh` 的幂等怎么实现（第 104 行的 `[[ -f "$ENV_FILE" ]]`）
- 为什么 `check_env_keys` 只警告不修改
- `gen_pw` 为什么不用 `tr | head`
- `deploy.sh` 等待 healthy 为什么要自己轮询而不是 `--wait`

**答辩会问**：`init.sh` 第二次执行为什么不覆盖 `.env`？是哪一行保证的？→ 第 104 行 `if [[ -f "$ENV_FILE" ]]`，进入后只调 `check_env_keys` 且只打印警告。

**自测**：删掉 `.env` 跑一次、再跑一次，用 `sha256sum` 对比；人为占一个端口跑 `deploy.sh`，看报错是否说清是端口问题。

### 4.3 脚本开发 B（M2 `analyze.sh`）

**必须懂**：
- 六个指标各自的 awk 片段在哪一行
- `details.tsv` 为什么要用 `Q/S/E/H` 前缀
- 为什么排序要加 `-k2,2` 和 `LC_ALL=C`
- 为什么用 `awk '$1=="Q"'` 而不是 `grep '^Q'`
- 坏行为什么要单独计数而不是直接丢

**答辩会问**：日志是 `.gz` 的，要改哪里？→ `setup_reader` 第 77–87 行，按后缀选 `gzip -dc`；不必改任何 awk。grep 没匹配到时脚本会怎样？→ 我没用 grep 分流，用 awk 过滤（awk 无匹配返回 0），就是为了避开 `pipefail` 下 grep 返回 1 的问题。

**自测**：`AWK=mawk`（用 PATH 注入）跑同一份日志，`diff` 两份 `summary.csv` 必须为空。

### 4.4 容器与镜像（M3 `Dockerfile` + M4 `compose.yml`）

**必须懂**：
- 非 root 的三件套（8080 / pid / temp_path），缺一个报什么错
- 为什么选 alpine：wget 与体积
- healthcheck 为什么打 `/healthz` 而不是 `/`
- **`access.log` 是符号链接**这件事，以及它为什么必须靠挂载解决
- `:ro` 为什么会让容器退出

**答辩会问**：为什么选这个基础镜像？换 alpine 会有什么问题？→ 选它是因为自带 wget 且体积小；换回 Debian 版（`nginx:latest`）healthcheck 就没 curl 也没 wget 可用，得额外装包。容器里 whoami 是谁？→ `nginx`，uid 101，靠 `USER nginx`。healthcheck 检查的是什么？→ 检查 HTTP 服务能否响应（`/healthz` 返回 200），不是检查进程在不在。

**自测**：`docker exec <c> whoami`；`docker logs <c> | grep -c healthz` 必须为 0；`ls -l data/logs/access.log` 必须有内容。

### 4.5 数据与巡检（M5 `check.sh` + `conf/crontab` + `tools/genlogs.sh`）

**必须懂**：
- 四类阈值怎么取（`df -P /`、`free`、`docker compose ps`、`ss`）
- 阈值为什么从 `.env` 读而不是写死
- cron 里为什么要绝对路径 + 重定向
- `alert.log` 的格式（时间戳 + 类型 + 数值）

**答辩会问**：cron 里为什么要写绝对路径？日志写到哪里？→ cron 的 PATH 与交互 shell 不同，且 cwd 不是仓库根；日志写 `data/logs/alert.log`，通过 `>> ... 2>&1` 重定向。

**自测**：`docker stop` 容器后 `./check.sh; echo $?` 必须为 1；把 `DISK_THRESHOLD` 调到 1 再跑，必须触发告警。

### 4.6 测试与文档

**必须懂**：
- `run-tests.sh` 的三节结构与 `want` 函数
- 断言为什么用 `assert_eq "描述" "期望" "实际"` 三参数
- 每类失败该看哪一节的输出
- 14 项验收清单逐项对应的命令

**答辩会问**：怎么证明指标是对的？→ 三层证据：8 行手工可算的 fixtures、10 万行与独立命令比对、`run-tests.sh` 47 项回归。

**自测**：故意改坏一个数字（比如把 `$9` 改成 `$8`），跑测试必须红；改回来后必须全绿。

## 5 答辩问题预演（课程 7.3 四类）

| 类别 | 可能的问题 | 答案要点 | 代码位置 |
|---|---|---|---|
| 脚本 | `init.sh` 第二次执行为什么不覆盖 `.env`？ | `[[ -f "$ENV_FILE" ]]` 分支只打印警告 | init.sh:104 |
| 脚本 | `grep` 没匹配到时脚本会怎样？你怎么处理？ | 没依赖 grep 分流；awk 无匹配返回 0，规避 `pipefail` | analyze.sh:140–147 |
| 脚本 | 日志是 `.gz` 的，要改哪里？ | 只改 `setup_reader` 选 `gzip -dc` | analyze.sh:77–87 |
| 容器 | 为什么选这个基础镜像？换 alpine 有什么问题？ | wget + 体积；Debian 版无 curl/wget | Dockerfile:11 |
| 容器 | 容器里 `whoami` 是谁？怎么改成非 root？ | `nginx`/uid 101；`USER nginx` + 三件套 | Dockerfile:33 |
| 容器 | healthcheck 检查的是什么？为什么用 wget？ | HTTP 200；alpine 自带 busybox wget | Dockerfile:39 |
| 编排 | `depends_on` 能保证 db 就绪吗？ | 不能，只保证启动顺序；要 `condition: service_healthy` | M4 待实现 |
| 编排 | `down` 与 `down -v` 差在哪？验收敢执行哪个？ | `-v` 删卷即删数据；只敢 `down` | 方案 5.5 |
| 协作 | 这个模块是谁写的？请他解释这段逻辑 | 每人按第 4 章准备本模块 3 个行号级问题 | — |

## 6 三十五分钟读代码的路线

给第一次接触代码的组员：

1. **5 分钟**：读 `README.md`，知道三条命令是什么
2. **5 分钟**：跑一遍 `./init.sh` 和 `./tests/run-tests.sh`，看输出长什么样
3. **10 分钟**：读自己模块那个脚本的 `main()` 函数，顺着调用往下走（不看细节）
4. **10 分钟**：读自己模块的核心函数（表在 2.1/2.2）
5. **5 分钟**：对照第 3 章契约表，确认自己的模块消费了谁的输出、产出了谁要用的东西

读完要做的事：按 v2.0 方案 6.4 交 300 字笔记（一句话概括 + 关键行号 + 1 条改进）。
