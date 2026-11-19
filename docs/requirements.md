# 《Unix与Linux系统》课程设计 · 需求原文

> 来源：`《Unix与Linux系统》课程设计（Shell与Docker）.docx`（用户提供的课程要求文件）
> 说明：本文档由原 docx 逐节转录为 Markdown，内容不删改；表格保留为 Markdown 表格，附录脚本骨架保留为代码块。
> 权威性：以课程原始 docx 为准，本文档仅作组内检索与引用索引。

---

## 封面

**《Unix与Linux系统》课程设计**

一键交付：基于 Shell 与 Docker 的日志分析服务

周期 4 周　|　3-6 人一组　|　环境 Ubuntu 22.04 + Docker 24 + Compose v2

说明：本设计承接第 2-14 讲的命令行、文本处理、Shell 编程、cron、容器与 Compose 内容，要求把"手工敲过的命令"变成"一条命令能交付的系统"。所有脚本必须可重复执行，所有服务必须能被一条命令拉起、被一份检查表验证。考核方式为小组现场向教师展示并接受提问。

---

## 一、项目背景与目标

学院课程网站每周要出一份访问情况报告：总访问量、独立 IP、TOP10 页面、5xx 错误分布、访问高峰时段。目前的做法是管理员登录服务器，手工 tail 日志、复制粘贴到 Excel，一次要花两小时，而且换台机器就复现不了。

本学期课程设计要解决这件事：做一个"一键部署、每天自动出报告"的小系统。它由一台 Linux 主机上的若干个 Shell 脚本与一组容器组成，新人拿到仓库后，执行一条命令就能把环境、服务与报告全部就绪。

项目目标（四条，验收时逐条对照）：

1. 环境可复现：clone 仓库后执行 `./init.sh` 与 `./deploy.sh`，10 分钟内跑通全流程；
2. 分析可信任：`analyze.sh` 能从原始日志算出指标，结果与手工核对一致；
3. 服务可托管：容器化部署，重启后自动恢复，健康状态可查询；
4. 运行可观测：巡检脚本 + cron 自动告警，异常能留下可追溯的日志。

---

## 二、设计目的与能力要求

通过一个完整的"交付"过程，把分散的命令与知识点串成工程能力：

| 能力 | 对应知识点（讲次） | 在本项目中的体现 |
|---|---|---|
| 命令行与文本处理 | 第 2-3 讲：grep/sed/awk、正则、重定向 | analyze.sh 的指标计算与报表生成 |
| Shell 编程 | 第 4-6 讲：变量、条件、循环、函数、参数校验 | 全部脚本的参数解析、错误处理、日志 |
| 系统与任务调度 | 第 5-6 讲：进程、cron、systemd | check.sh 定时巡检、异常退出码 |
| 容器与镜像 | 第 11-12 讲：Dockerfile、分层、多阶段 | Dockerfile 构建 web 服务镜像 |
| 编排与交付 | 第 13-14 讲：卷、网络、Compose、健康检查 | compose.yml 一键起停、数据持久化 |
| 工程规范 | 第 15-16 讲：文档、演示 | 仓库结构、README、8 分钟演示 |

---

## 三、核心知识与技能点

项目必须用到下列技能，验收时会随机抽查其中任意一项：

| 类别 | 必须掌握 |
|---|---|
| Shell 基础 | shebang、`set -euo pipefail`、变量与引号、位置参数、退出码 |
| 流程控制 | if/`[[ ]]`、case、for、`while read`、函数与 local |
| 文本处理 | `grep -c/-oE/-v`、sed 替换、awk 取列与聚合、sort/uniq、cut |
| 系统管理 | chmod/chown、crontab、df/free/ps、ss、systemctl |
| 容器 | docker build/run/ps/logs/exec、卷与端口映射、Dockerfile 指令 |
| 编排 | compose.yml 三块结构、.env、healthcheck、depends_on、日志限制 |
| 工程实践 | Git 提交规范、README 撰写、脚本幂等与可重复执行 |

---

## 四、项目任务与功能要求

### 4.1 总体任务

交付一个名为 `logops` 的仓库，提供五个可执行脚本与一组容器配置，实现"初始化 → 分析 → 部署 → 巡检 → 一键交付"的闭环。目录结构要求：

```text
logops/
├── init.sh                 # 初始化：建目录、查依赖、生成 .env
├── analyze.sh              # 日志分析：输出 report.md 与 summary.csv
├── check.sh                # 巡检：磁盘/内存/容器/端口，异常告警
├── deploy.sh               # 一键部署：build → up → 等待健康 → 出报告
├── Dockerfile              # web 服务镜像（多阶段可选）
├── compose.yml             # web + db（可选）+ 卷 + 网络 + healthcheck
├── .env.example            # 环境变量模板（密码不入库）
├── conf/                   # nginx 配置、crontab 模板
├── data/logs/              # 挂载进容器的日志目录
├── out/                    # 生成的报告（不入库）
└── README.md               # 部署说明、验收步骤、分工表
```

### 4.2 必做功能（M1-M5，缺一不可）

| 模块 | 脚本 | 功能要求 | 验收方式 |
|---|---|---|---|
| M1 | init.sh | 检查 bash/docker/compose/awk 是否存在；创建 data/logs、out、conf；从 .env.example 生成 .env 并写入随机密码；重复执行不报错、不覆盖已有 .env | 连跑两次，第二次输出"已存在，跳过" |
| M2 | analyze.sh | 接收 `--log`、`--top`、`--out` 三个参数；输出总请求数、独立 IP 数、TOP N URL、状态码分布、5xx 明细、按小时请求趋势；生成 report.md 与 summary.csv | 与手工 grep/awk 结果误差为 0 |
| M3 | Dockerfile | 基于 nginx 或 python 基础镜像；非 root 运行；暴露端口；含健康检查；镜像体积合理（<300MB） | `docker images` 查看体积；curl 健康检查 |
| M4 | compose.yml | web 服务挂载 data/logs 与 conf；配置 healthcheck；端口仅暴露必要一个；日志配 max-size；可选 db 服务并用 volume 持久化 | `docker compose config` 通过；`compose ps` 显示 healthy |
| M5 | check.sh + deploy.sh | check.sh 磁盘>80%、内存>90%、容器非 running 时告警并 exit 1；deploy.sh 串起 build→up→等待 healthy→执行 analyze→打印访问地址，失败即回滚 | 故意停容器，check.sh 必须报错；deploy.sh 一次跑通 |

### 4.3 选做功能

1. 多阶段构建：把镜像从 300MB 压到 100MB 以内，并在报告里给出对比；
2. 日志轮转：容器日志与 report 目录按天清理，保留 7 天；
3. 备份与恢复：数据库全量备份 + 恢复演练，脚本化并留验证记录；
4. 简易看板：用静态页面展示 summary.csv 的关键指标（可由 nginx 直接托管）；
5. 一次 make 或 just 封装（Makefile 里定义 build/up/check/report 四个目标）。

### 4.4 技术约束

1. 只允许使用 bash 与 docker/docker compose，不得依赖在线服务；
2. 所有密码、端口来自 `.env`，禁止硬编码进脚本与镜像；
3. 所有脚本必须可重复执行（幂等），并能被 cron 调用；
4. 脚本要有 `--help`，参数缺失时打印用法并 exit 2；
5. 任何一步失败都要有明确报错，不允许"静默成功"。

---

## 五、分组与分工

### 5.1 组队规则

3-6 人一组，设组长 1 名，会写脚本的、会容器配置的、会做文档与演示的各有人。

### 5.2 角色建议（可一人多岗，但每个岗位须有人负责）

| 角色 | 主要职责 | 对应模块 |
|---|---|---|
| 组长 / 架构 | 拆分任务、把控进度、评审提交、对外沟通 | 整体 |
| 脚本开发 A | init.sh、deploy.sh 与参数解析、错误处理 | M1、M5 |
| 脚本开发 B | analyze.sh 的指标算法与报表格式 | M2 |
| 容器与镜像 | Dockerfile、compose.yml、卷与网络、健康检查 | M3、M4 |
| 数据与巡检 | 日志准备、check.sh、crontab、告警规则 | M5 |
| 测试与文档 | 验收清单逐项测试、README、报告、演示材料 | 全部 |

分工表模板（提交时附在 README 末尾）：姓名 / 学号 / 角色 / 负责模块。

---

## 六、进度安排（4 周）

| 周次 | 主要任务 | 每周产出 | 周检查点（教师抽查） |
|---|---|---|---|
| 第 1 周 | 需求分析、仓库初始化、目录结构与 Git 规范；完成 init.sh 骨架；准备 10 万行样例日志 | 仓库可 clone、init.sh 可运行、分工表 | 检查：init.sh 连跑两次，幂等；目录符合 4.1 |
| 第 2 周 | 实现 analyze.sh 全部指标；编写 Dockerfile 并成功构建镜像；脚本统一参数与日志风格 | report.md 样例、可运行镜像 | 检查：随机抽一条指标，与手工结果比对；镜像可 curl 通 |
| 第 3 周 | 编写 compose.yml（卷/网络/健康检查）；接入 check.sh 与 crontab；实现 deploy.sh 串起全流程 | 一键部署成功、巡检告警可触发 | 检查：`docker compose up -d` 后全绿；故意停容器能告警 |
| 第 4 周 | 完善异常处理与文档；跑验收清单；准备 8 分钟演示与问答；提交与互评 | 完整仓库 + 报告 + 演示录屏 | 检查：验收清单 12 项全绿；现场演示 + 提问 |

时间提示：第 1 周结束必须能"跑起来"，第 2 周结束必须能"算对"，第 3 周结束必须能"一键起"，第 4 周只做打磨与答辩，不再加新功能。

---

## 七、成果提交与现场展示

### 7.1 提交方式：小组现场展示 + 教师提问

各组按抽签顺序，单独向教师做一次现场展示：先在教师指定的机器上把系统跑起来，再讲设计取舍，最后回答提问。每组的展示与提问合计 15 分钟（演示 8 分钟 + 提问 7 分钟）。

| 环节 | 时长 | 要求 |
|---|---|---|
| 环境确认 | 提前 10 分钟 | 在自己机器或指定虚拟机上确认 docker、compose 可用，数据已就位 |
| 现场演示 | 8 分钟 | 从 clone 开始，按 7.2 的六步走完，中途不切换 PPT |
| 设计讲解 | 含在 8 分钟内 | 讲清三个取舍：为什么这样分脚本、为什么这样分容器、为什么这样定阈值 |
| 教师提问 | 7 分钟 | 按 7.3 的四类问题随机抽取 |

### 7.2 现场演示六步（按顺序，缺一步即扣分）

1. 展示仓库结构：`git log` 一屏、目录树、README 三条命令；
2. 执行 `./init.sh` 两次：第二次必须提示"已存在，跳过"，证明幂等；
3. 执行 `./analyze.sh`：现场跑一次，打开 report.md 与 summary.csv，随机指一个指标让教师核对；
4. 执行 `./deploy.sh`：等待 healthy，浏览器打开页面，证明服务真的在跑；
5. 制造一次故障：`docker stop` 掉 web，执行 `./check.sh`，看到非 0 退出码与 alert.log；
6. 说明数据落在哪：`docker inspect` 看 Mounts，证明卷生效、重启不丢数据。

### 7.3 教师提问范围（四类，现场随机）

| 类别 | 考察点 | 示例问题 |
|---|---|---|
| 脚本与文本处理 | 是否真懂自己写的每一行 | init.sh 第二次执行为什么不覆盖 .env？哪一行保证的？<br>grep 没匹配到时脚本会怎样？你怎么处理？<br>日志是 .gz 的，analyze.sh 要改哪里？ |
| 容器与镜像 | 是否理解隔离与分层 | 为什么选这个基础镜像？换成 alpine 会有什么问题？<br>容器里 whoami 是谁？怎么改成非 root？<br>healthcheck 检查的是什么？为什么用 wget 不用 curl？ |
| 编排与运维 | 是否踩过真实的坑 | depends_on 能保证 db 就绪吗？你的方案是什么？<br>compose down 与 down -v 差在哪？验收时你敢执行哪个？<br>cron 里为什么要写绝对路径？你的日志写到哪里？ |
| 协作与工程 | 分工是否真实、能否复盘 | 这个模块是谁写的？请他解释这段逻辑；<br>Git 里为什么有一次 revert？当时出了什么问题？ |

### 7.4 展示当天需准备的材料

| 序号 | 材料 | 用途 |
|---|---|---|
| 1 | 可运行的环境 | 现场演示用；网络可断开，镜像需提前拉好 |
| 2 | Git 仓库 | 现场打开 git log 与关键文件 |
| 3 | README.md | 展示时照着念三条命令即可 |
| 4 | 设计报告 | 交给教师存档，结构见 7.5 |
| 5 | 分工表 | 含姓名、学号、角色、负责模块 |

### 7.5 报告结构（8 节）

1. 需求与范围：解决什么问题、明确不做什么；
2. 总体设计：组件图、数据流（日志 → 分析 → 报告 → 展示）；
3. 脚本设计：每个脚本的参数、流程、异常处理；关键代码片段；
4. 容器与编排：镜像分层、卷与网络选择理由、健康检查设计；
5. 关键问题与解决：至少写 2 个真实踩坑（现象—定位—修复）；
6. 测试与验收：验收清单逐项结果与截图；
7. 分工与贡献：角色、工作量、互评结论；
8. 不足与改进：如果再做两周，会改什么。

---

## 八、验收与评分

### 8.1 验收清单（现场逐项演示并打勾，缺项按比例扣分）

| # | 验收项 | 判定标准 | ☐ |
|---|---|---|---|
| 1 | 仓库可 clone | 无缺失文件，README 三条命令清晰 | |
| 2 | init.sh 幂等 | 连续执行两次，第二次不报错不改 .env | |
| 3 | 依赖检查 | 缺少 docker 时给出明确提示并 exit 1 | |
| 4 | analyze.sh 参数 | 缺参打印用法并 exit 2；`--help` 可用 | |
| 5 | 指标正确 | 现场抽查 3 个指标与手工结果一致 | |
| 6 | 报表完整 | report.md 含 6 类指标，summary.csv 可被 Excel 打开 | |
| 7 | 镜像可用 | `docker images` 可见，容器内服务可访问 | |
| 8 | 非 root 运行 | `docker exec` 查 whoami 非 root | |
| 9 | 健康检查 | `compose ps` 显示 healthy | |
| 10 | 数据持久化 | 重启后日志与报告仍在（卷生效） | |
| 11 | 巡检告警 | 停掉容器后 check.sh exit 1 并写 alert.log | |
| 12 | 一键部署 | deploy.sh 从零到可访问不超过 10 分钟 | |
| 13 | 讲解清楚 | 能说清三个取舍（分脚本、分容器、定阈值） | |
| 14 | 组员应答 | 能回答自己负责模块的问题 | |

### 8.2 评分表（总分 100）

| 项目 | 分值 | 评分要点 |
|---|---|---|
| 过程与协作 | 25 | 四次周检查点各 5 分；Git 提交质量与组内互评 5 分 |
| 功能实现 | 40 | M1-M4 各 6 分，M5 与整体集成 16 分 |
| 现场展示与答辩 | 25 | 演示是否跑通 10 分；讲解取舍 8 分；回答提问 7 分 |
| 文档与报告 | 10 | README 可照做、报告 8 节完整、截图与数据真实 |

扣分情形：演示环境没准备好 -5；只有 PPT 没有实际运行 -10；答不出自己模块的问题 -5。

---

## 九、常见问题与注意事项

1. 密码写进脚本或镜像：一旦提交即视为不合格，必须改用 `.env`；
2. 脚本不可重复执行：第二次运行就报"目录已存在""端口被占用"，用判断与 `--force` 处理；
3. cron 不执行：PATH 与交互环境不同，命令写绝对路径、输出重定向到日志；
4. 端口冲突：宿主 80 端口常被占用，使用 8080 或从 `.env` 读取；
5. 日志丢失：容器不加卷，删容器日志即消失；日志必须挂到 `data/logs`；
6. 只在自己机器上能跑：验收在教师指定的干净环境中进行，必须从 clone 开始。

---

## 十、参考资料

1. 课程讲义第 2-6 讲、第 11-14 讲；《Docker 容器技术》操作手册。
2. GNU Bash Reference Manual. https://www.gnu.org/software/bash/manual/
3. Docker Documentation. https://docs.docker.com/
4. ShellCheck. https://www.shellcheck.net/（提交前请把告警清零）

---

## 附录 A　脚本骨架

### A.1 init.sh 骨架

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

log(){ printf '[%s] %s\n' "$(date +%T)" "$*"; }
need(){ command -v "$1" >/dev/null || { log "缺少依赖: $1"; exit 1; }; }

for c in bash docker awk sed grep; do need "$c"; done
docker compose version >/dev/null || { log '缺少 docker compose'; exit 1; }

mkdir -p data/logs out conf
if [[ -f .env ]]; then log '.env 已存在，跳过'; else
  cp .env.example .env
  sed -i "s/^WEB_PORT=.*/WEB_PORT=8080/" .env
  log '.env 已生成'
fi
log '初始化完成'
```

### A.2 analyze.sh 核心片段（指标计算）

```bash
total=$(wc -l < "$LOG")
ips=$(awk '{print $1}' "$LOG" | sort -u | wc -l)
echo "| 总请求 | $total |" >> "$OUT/report.md"
echo "| 独立 IP | $ips |" >> "$OUT/report.md"
awk '{print $7}' "$LOG" | sort | uniq -c | sort -rn | head -n "$TOP"
awk '$9 ~ /^5/ {c++} END{print "5xx:", c+0}' "$LOG"
```

### A.3 compose.yml 骨架

```yaml
services:
  web:
    build: .
    image: logops-web:1.0
    ports: ["${WEB_PORT:-8080}:80"]
    volumes:
      - ./data/logs:/var/log/nginx:ro
      - ./out:/usr/share/nginx/html/report:ro
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1/"]
      interval: 10s
      retries: 3
    logging:
      options: {max-size: "10m", max-file: "3"}
```

### A.4 check.sh 判定片段

```bash
use=$(df -P / | awk 'NR==2{gsub(/%/,"",$5); print $5}')
mem=$(free | awk '/Mem:/{printf "%d", $3/$2*100}')
[[ $use -gt $DISK ]] && { log "磁盘 ${use}% 超阈值"; rc=1; }
[[ $mem -gt $MEM ]] && { log "内存 ${mem}% 超阈值"; rc=1; }
docker compose ps --status running | grep -q web || { log 'web 未运行'; rc=1; }
exit ${rc:-0}
```
