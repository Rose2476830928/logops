#!/usr/bin/env bash
# init.sh —— logops 初始化：检查依赖、建目录、从模板生成 .env（幂等）
# 退出码：0 成功（含"已存在，跳过"）｜1 依赖或环境不满足｜2 参数错误
set -euo pipefail
cd "$(dirname "$0")"

SCRIPT_NAME="$(basename "$0")"
REPO_ROOT="$(pwd)"
LOG_DIR="$REPO_ROOT/data/logs"
OUT_DIR="$REPO_ROOT/out"
CONF_DIR="$REPO_ROOT/conf"
ENV_FILE="$REPO_ROOT/.env"
ENV_TPL="$REPO_ROOT/.env.example"
PW_LEN=16

log()  { printf '[%s] %s\n' "$(date +%T)" "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s: %s\n' "$1" "${2:-}" >&2; exit 1; }

usage() {
    cat <<'EOF'
用法: ./init.sh

无参数运行。重复执行是安全的：已存在的 .env 不会被覆盖。
退出码: 0 成功 / 1 依赖或环境不满足 / 2 参数错误

  -h, --help   显示本帮助并退出
EOF
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "依赖" "缺少命令: $1"
}

gen_pw() {
    # dd + tr + cut：不依赖 openssl；不用 `tr | head`，避免 pipefail 下的 SIGPIPE(141)
    # 1024 字节：可打印字母数字约占 24%，过滤后约 240 字符，远多于 PW_LEN
    dd if=/dev/urandom bs=1024 count=1 2>/dev/null \
        | LC_ALL=C tr -dc 'A-Za-z0-9' \
        | cut -c1-"$PW_LEN"
}

check_platform() {
    case "$REPO_ROOT" in
        /mnt/[a-z]/*)
            warn "仓库位于 Windows 挂载盘（$REPO_ROOT）"
            warn "容器卷权限与非 root 写入可能异常，chmod 也不会生效"
            warn "建议把仓库放到 Linux 侧（如 ~/logops）后再跑容器"
            ;;
    esac
}

check_deps() {
    local c os_type
    for c in bash docker awk sed grep mktemp date; do
        need "$c"
    done
    docker compose version >/dev/null 2>&1 \
        || die "依赖" "docker compose 不可用：Ubuntu 上执行 sudo apt install docker-compose-v2；若用 Docker Desktop，确认 WSL 集成已开启"
    docker info >/dev/null 2>&1 \
        || die "依赖" "docker 守护进程未运行：先启动 Docker Desktop，或执行 sudo systemctl start docker"
    # 防止 PATH 命中 Windows 的 docker.exe（WSL interop 会把 Windows PATH 追加进来）
    os_type="$(docker version --format '{{.Server.Os}}' 2>/dev/null || true)"
    [[ "$os_type" == "linux" ]] \
        || die "依赖" "docker 引擎不是 Linux（Server.Os=${os_type:-unknown}），请检查 PATH 里的 docker 指向"
}

make_dirs() {
    local d
    for d in "$LOG_DIR" "$OUT_DIR" "$CONF_DIR"; do
        if [[ -d "$d" ]]; then
            log "目录已存在，跳过: ${d#"$REPO_ROOT"/}"
        else
            mkdir -p "$d"
            log "创建目录: ${d#"$REPO_ROOT"/}"
        fi
    done
    [[ -f "$LOG_DIR/.gitkeep" ]] || : > "$LOG_DIR/.gitkeep"
    [[ -f "$OUT_DIR/.gitkeep" ]] || : > "$OUT_DIR/.gitkeep"
    # 容器内 nginx 以非 root 运行，需要可写日志目录；取舍见 docs/risks.md R15
    if chmod 777 "$LOG_DIR" 2>/dev/null; then
        log "日志目录权限: 777（供容器内非 root 进程写入）"
    else
        warn "无法修改 $LOG_DIR 权限，容器可能无法写日志"
    fi
}

check_env_keys() {
    # .env 已存在时只提示缺字段，不修改文件——保证"重复执行不改 .env"
    local missing="" key
    while IFS= read -r line; do
        [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)= ]] || continue
        key="${BASH_REMATCH[1]}"
        grep -q "^${key}=" "$ENV_FILE" || missing="$missing $key"
    done < "$ENV_TPL"
    if [[ -n "$missing" ]]; then
        warn "已有 .env 缺少字段:$missing"
        warn "为不覆盖你的配置，脚本不会自动补；请手动补齐后重跑（模板见 .env.example）"
    fi
}

ensure_env() {
    local pw
    if [[ -f "$ENV_FILE" ]]; then
        log ".env 已存在，跳过（不覆盖已有配置）"
        check_env_keys
        return 0
    fi
    [[ -f "$ENV_TPL" ]] || die "初始化" "缺少模板文件 .env.example"
    cp "$ENV_TPL" "$ENV_FILE"
    pw="$(gen_pw)"
    [[ ${#pw} -eq $PW_LEN ]] || die "初始化" "随机密码生成失败（长度 ${#pw}，期望 $PW_LEN）"
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${pw}|" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    log ".env 已生成（DB_PASSWORD 为 ${PW_LEN} 位随机值，不打印内容）"
}

awk_info() {
    if awk --version >/dev/null 2>&1; then
        awk --version 2>&1 | sed -n '1p'
    else
        awk -W version 2>&1 | sed -n '1p'
    fi
}

write_report() {
    local f="$LOG_DIR/init-report.txt" sc
    sc="未安装"
    if command -v shellcheck >/dev/null 2>&1; then
        sc="$(shellcheck --version | awk '/^version:/{print $2}' | sed -n '1p')"
    fi
    {
        printf 'date: %s\n' "$(date -Is 2>/dev/null || date)"
        printf 'repo: %s\n' "$REPO_ROOT"
        printf 'kernel: %s\n' "$(uname -srm)"
        printf 'bash: %s\n' "$BASH_VERSION"
        printf 'awk: %s\n' "$(awk_info)"
        printf 'shellcheck: %s\n' "${sc:-未安装}"
        printf 'docker: %s\n' "$(docker --version)"
        printf 'compose: %s\n' "$(docker compose version --short 2>/dev/null || docker compose version | sed -n '1p')"
    } > "$f"
    log "环境报告: ${f#"$REPO_ROOT"/}"
}

main() {
    if [[ $# -gt 0 ]]; then
        case "$1" in
            -h|--help) usage; exit 0 ;;
            *) printf '[ERROR] 参数: 未知参数 %s\n' "$1" >&2; usage; exit 2 ;;
        esac
    fi
    log "开始初始化: $REPO_ROOT"
    check_platform
    check_deps
    make_dirs
    ensure_env
    write_report
    log "初始化完成（$SCRIPT_NAME）"
}

main "$@"
