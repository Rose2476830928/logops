#!/usr/bin/env bash
# shellcheck disable=SC2016  # printf 的格式串里用反引号做 Markdown 代码标记，必须保持单引号不展开
# analyze.sh —— 从 nginx combined 访问日志算出六类指标，输出 report.md 与 summary.csv
#
# 六类指标（课程 M2）：
#   1 总请求数   2 独立 IP   3 TOP N URL   4 状态码分布   5 5xx 明细   6 按小时趋势
#
# 兼容性：只使用 POSIX awk（不用 gensub/asort/match 三参数/正则 \s），
#        在 Ubuntu 22.04 的 mawk 与 25.10 的 gawk 上结果一致。
# 退出码：0 成功 / 1 读取失败或依赖缺失 / 2 参数错误
set -euo pipefail
cd "$(dirname "$0")"

REPO_ROOT="$(pwd)"
DEFAULT_OUT="$REPO_ROOT/out"
DEFAULT_TOP=10

LOG_FILE=""
TOP_N=""
OUT_ARG=""
TMPD=""
READER=()

log()  { printf '[%s] %s\n' "$(date +%T)" "$*"; }
die()  { printf '[ERROR] %s: %s\n' "$1" "${2:-}" >&2; exit 1; }

usage() {
    cat <<'EOF'
用法: ./analyze.sh --log <file> [--top N] [--out dir]

  --log <file>   必填，待分析的访问日志（支持 .gz）
  --top <N>      TOP N 的 N，默认 10
  --out <dir>    产物目录，默认 ./out
  -h, --help     显示本帮助并退出

产物:
  <out>/report.md     六类指标的可读报告
  <out>/summary.csv   关键指标（metric,value），可直接用 Excel 打开
退出码: 0 成功 / 1 读取失败或依赖缺失 / 2 参数错误
EOF
}

need() { command -v "$1" >/dev/null 2>&1 || die "依赖" "缺少命令: $1"; }

cleanup() {
    # 清理失败不得改变脚本退出码：trap EXIT 的返回值会覆盖 $?
    if [[ -n "$TMPD" && -d "$TMPD" ]]; then
        rm -rf "$TMPD" 2>/dev/null || true
    fi
    return 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --log)
                [[ $# -ge 2 ]] || { printf '[ERROR] 参数: --log 缺少值\n' >&2; usage; exit 2; }
                LOG_FILE="$2"; shift 2 ;;
            --top)
                [[ $# -ge 2 ]] || { printf '[ERROR] 参数: --top 缺少值\n' >&2; usage; exit 2; }
                TOP_N="$2"; shift 2 ;;
            --out)
                [[ $# -ge 2 ]] || { printf '[ERROR] 参数: --out 缺少值\n' >&2; usage; exit 2; }
                OUT_ARG="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) printf '[ERROR] 参数: 未知参数 %s\n' "$1" >&2; usage; exit 2 ;;
        esac
    done
    [[ -n "$LOG_FILE" ]] || { printf '[ERROR] 参数: 缺少 --log\n' >&2; usage; exit 2; }
    TOP_N="${TOP_N:-$DEFAULT_TOP}"
    OUT_ARG="${OUT_ARG:-$DEFAULT_OUT}"
    [[ "$TOP_N" =~ ^[0-9]+$ ]] || { printf '[ERROR] 参数: --top 必须是整数，得到 %s\n' "$TOP_N" >&2; exit 2; }
    [[ "$TOP_N" -gt 0 ]] || { printf '[ERROR] 参数: --top 必须大于 0\n' >&2; exit 2; }
    [[ -r "$LOG_FILE" ]] || die "读取" "日志文件不存在或不可读: $LOG_FILE"
}

setup_reader() {
    case "$LOG_FILE" in
        *.gz)
            need gzip
            READER=(gzip -dc)
            ;;
        *)
            READER=(cat)
            ;;
    esac
}

# 一次扫描算出：总行数、无法解析行数、独立 IP、2xx/3xx/4xx/5xx、峰值小时
calc_core() {
    local out
    out="$("${READER[@]}" "$LOG_FILE" | awk '
        NF == 0 { next }
        {
            total++
            if (NF < 9 || $9 !~ /^[0-9][0-9][0-9]$/) { bad++; next }
            ips[$1] = 1
            k = substr($9, 1, 1)
            if (k == "2") s2++
            else if (k == "3") s3++
            else if (k == "4") s4++
            else if (k == "5") s5++
            n = split($4, t, ":")
            if (n >= 2 && t[2] ~ /^[0-9][0-9]$/) hour[t[2]]++
        }
        END {
            u = 0
            for (x in ips) u++
            ph = "-"; pc = 0
            for (h in hour) {
                if (hour[h] > pc) { pc = hour[h]; ph = h }
            }
            printf "%d %d %d %d %d %d %d %s %d\n", total + 0, bad + 0, u + 0, s2 + 0, s3 + 0, s4 + 0, s5 + 0, ph, pc + 0
        }')"
    read -r TOTAL BAD UNIQ_IPS S2 S3 S4 S5 PEAK_HOUR PEAK_COUNT <<< "$out" || true
}

# 一次扫描把四类明细写进 details.tsv，带类型前缀 Q=URL S=状态码 E=5xx H=小时
# 这样全文件只解析两次（core 一次、details 一次），10 万行日志也不会慢
calc_details() {
    "${READER[@]}" "$LOG_FILE" | awk '
        NF >= 9 && $9 ~ /^[0-9][0-9][0-9]$/ {
            if ($7 != "") url[$7]++
            st[$9]++
            if ($9 ~ /^5[0-9][0-9]$/) e5[$7]++
        }
        NF >= 4 {
            n = split($4, t, ":")
            if (n >= 2 && t[2] ~ /^[0-9][0-9]$/) hr[t[2]]++
        }
        END {
            for (x in url) printf "Q\t%d\t%s\n", url[x], x
            for (x in st)  printf "S\t%s\t%d\n", x, st[x]
            for (x in e5)  printf "E\t%d\t%s\n", e5[x], x
            for (x in hr)  printf "H\t%s\t%d\n", x, hr[x]
        }' > "$TMPD/details.tsv"

    awk -F'\t' '$1 == "Q" { print $2 "\t" $3 }' "$TMPD/details.tsv" \
        | sort -k1,1nr | sed -n "1,${TOP_N}p" > "$TMPD/top.tsv"
    awk -F'\t' '$1 == "S" { print $2 "\t" $3 }' "$TMPD/details.tsv" \
        | sort -k1,1n > "$TMPD/status.tsv"
    awk -F'\t' '$1 == "E" { print $2 "\t" $3 }' "$TMPD/details.tsv" \
        | sort -k1,1nr > "$TMPD/err5xx.tsv"
    awk -F'\t' '$1 == "H" { print $2 "\t" $3 }' "$TMPD/details.tsv" \
        | sort -k1,1 > "$TMPD/hour.tsv"

    if [[ -s "$TMPD/top.tsv" ]]; then
        TOP_COUNT="$(sed -n '1p' "$TMPD/top.tsv" | cut -f1)"
        TOP_URL="$(sed -n '1p' "$TMPD/top.tsv" | cut -f2)"
    else
        TOP_COUNT=0
        TOP_URL="-"
    fi
}

# 百分比与柱状图用 bash 算术实现：每行表格都 fork 一次 awk 会让 report 生成慢十倍
pct() {
    local n="$1" t="$2" v
    if [[ "$t" -le 0 ]]; then
        printf '0.00'
        return 0
    fi
    v=$(( (n * 10000 + t / 2) / t ))
    printf '%d.%02d' $(( v / 100 )) $(( v % 100 ))
}

bar() {
    local c="$1" m="$2" n=0 i s=""
    if [[ "$m" -le 0 ]]; then
        return 0
    fi
    n=$(( c * 40 / m ))
    if [[ "$n" -lt 1 && "$c" -gt 0 ]]; then
        n=1
    fi
    for (( i = 0; i < n; i++ )); do
        s+="#"
    done
    printf '%s' "$s"
}

max_of_hours() {
    local m=0 _h _c
    if [[ -s "$TMPD/hour.tsv" ]]; then
        while IFS=$'\t' read -r _h _c; do
            if [[ "$_c" -gt "$m" ]]; then
                m="$_c"
            fi
        done < "$TMPD/hour.tsv"
    fi
    printf '%s' "$m"
}

write_report() {
    local f="$OUT_ARG/report.md" max_hour ts u cnt
    max_hour="$(max_of_hours)"

    {
        printf '# 访问日志分析报告\n\n'
        printf '| 项 | 值 |\n|---|---|\n'
        printf '| 输入文件 | `%s` |\n' "$LOG_FILE"
        printf '| 生成时间 | %s |\n' "$(date -Is 2>/dev/null || date)"
        printf '| 生成命令 | `./analyze.sh --log %s --top %s --out %s` |\n' "$LOG_FILE" "$TOP_N" "$OUT_ARG"
        printf '| 总请求数 | %s |\n' "$TOTAL"
        printf '| 独立 IP | %s |\n' "$UNIQ_IPS"
        printf '| 无法解析行 | %s |\n\n' "$BAD"

        printf '## 1 总览\n\n'
        printf '| 指标 | 数值 | 占比 |\n|---|---|---|\n'
        printf '| 总请求数 | %s | 100.00%% |\n' "$TOTAL"
        printf '| 2xx 成功 | %s | %s%% |\n' "$S2" "$(pct "$S2" "$TOTAL")"
        printf '| 3xx 重定向 | %s | %s%% |\n' "$S3" "$(pct "$S3" "$TOTAL")"
        printf '| 4xx 客户端错误 | %s | %s%% |\n' "$S4" "$(pct "$S4" "$TOTAL")"
        printf '| 5xx 服务端错误 | %s | %s%% |\n\n' "$S5" "$(pct "$S5" "$TOTAL")"

        printf '## 2 TOP %s URL\n\n' "$TOP_N"
        printf '| 排名 | URL | 请求数 | 占比 |\n|---|---|---|---|\n'
        ts=0
        while IFS=$'\t' read -r cnt u; do
            ts=$((ts + 1))
            printf '| %s | `%s` | %s | %s%% |\n' "$ts" "$u" "$cnt" "$(pct "$cnt" "$TOTAL")"
        done < "$TMPD/top.tsv"
        if [[ "$ts" -eq 0 ]]; then
            printf '| - | （无数据） | 0 | 0.00%% |\n'
        fi
        printf '\n'

        printf '## 3 状态码分布\n\n'
        printf '| 状态码 | 次数 | 占比 |\n|---|---|---|\n'
        ts=0
        while IFS=$'\t' read -r cnt u; do
            ts=$((ts + 1))
            printf '| %s | %s | %s%% |\n' "$u" "$cnt" "$(pct "$cnt" "$TOTAL")"
        done < "$TMPD/status.tsv"
        if [[ "$ts" -eq 0 ]]; then
            printf '| - | 0 | 0.00%% |\n'
        fi
        printf '\n'

        printf '## 4 5xx 明细（按 URL）\n\n'
        if [[ -s "$TMPD/err5xx.tsv" ]]; then
            printf '| URL | 5xx 次数 |\n|---|---|\n'
            while IFS=$'\t' read -r cnt u; do
                printf '| `%s` | %s |\n' "$u" "$cnt"
            done < "$TMPD/err5xx.tsv"
        else
            printf '无 5xx 记录。\n'
        fi
        printf '\n'

        printf '## 5 按小时请求趋势\n\n'
        printf '| 小时 | 请求数 | 分布 |\n|---|---|---|\n'
        ts=0
        while IFS=$'\t' read -r h cnt; do
            ts=$((ts + 1))
            printf '| %s:00 | %s | %s |\n' "$h" "$cnt" "$(bar "$cnt" "$max_hour")"
        done < "$TMPD/hour.tsv"
        if [[ "$ts" -eq 0 ]]; then
            printf '| - | 0 | |\n'
        fi
        printf '\n'
        printf '> 峰值时段：%s 点，共 %s 次请求。\n' "$PEAK_HOUR" "$PEAK_COUNT"
    } > "$f"
}

write_csv() {
    local f="$OUT_ARG/summary.csv"
    {
        printf 'metric,value\n'
        printf 'total_requests,%s\n' "$TOTAL"
        printf 'unique_ips,%s\n' "$UNIQ_IPS"
        printf 'top_url,"%s"\n' "$TOP_URL"
        printf 'top_url_count,%s\n' "$TOP_COUNT"
        printf 'status_2xx,%s\n' "$S2"
        printf 'status_3xx,%s\n' "$S3"
        printf 'status_4xx,%s\n' "$S4"
        printf 'status_5xx,%s\n' "$S5"
        printf 'peak_hour,%s\n' "$PEAK_HOUR"
        printf 'peak_hour_count,%s\n' "$PEAK_COUNT"
        printf 'unparsed_lines,%s\n' "$BAD"
    } > "$f"
}

main() {
    parse_args "$@"
    need awk
    need sort
    need sed
    need cut
    need mktemp
    setup_reader
    mkdir -p "$OUT_ARG"
    TMPD="$(mktemp -d)"
    trap cleanup EXIT

    log "开始分析: $LOG_FILE (top=$TOP_N)"
    calc_core
    calc_details
    write_report
    write_csv
    log "完成: $OUT_ARG/report.md, $OUT_ARG/summary.csv（总请求 $TOTAL，独立 IP $UNIQ_IPS）"
    if [[ "$BAD" -gt 0 ]]; then
        printf '[WARN] %s 行无法解析（字段数不足 9 或状态码非三位数字），已跳过\n' "$BAD" >&2
    fi
}

main "$@"
