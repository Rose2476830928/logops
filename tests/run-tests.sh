#!/usr/bin/env bash
# tests/run-tests.sh —— 阶段性回归测试
#
# 目的：每写完一个脚本就把它纳入这里，后续开发前先跑一遍，
#       确保"后面的代码建在能跑的地基上"，而不是建在一堆没验证的假设上。
#
# 用法：./tests/run-tests.sh          # 全部
#       ./tests/run-tests.sh m2       # 只跑某一节
# 退出码：0 全部通过；1 有失败
#
# 注意：本脚本刻意不启用 set -e —— 单个用例失败要继续跑完，才能一次看到全部问题。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
TMP="$(mktemp -d)"
# shellcheck disable=SC2329  # 由 trap 调用，shellcheck 不追踪间接调用
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

PASS=0
FAIL=0
SKIP=0
ONLY="${1:-all}"

ok()   { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n         期望: %s\n         实际: %s\n' "$1" "$2" "$3"; }
skip() { SKIP=$((SKIP + 1)); printf '  [SKIP] %s\n' "$1"; }

assert_eq() {
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "$2" "$3"; fi
}

csv_val() {
    awk -F, -v k="$2" '$1 == k { print $2; exit }' "$1" 2>/dev/null
}

want() {
    [[ "$ONLY" == "all" || "$ONLY" == "$1" ]]
}

# ---------------------------------------------------------------- M1 init.sh
if want m1; then
    printf '\n=== M1 init.sh ===\n'
    if ! docker info >/dev/null 2>&1; then
        skip "init.sh 全部用例（docker 守护进程不可用）"
    else
        W="$TMP/init"
        mkdir -p "$W"
        cp init.sh .env.example "$W/"

        RUN_LOG="$TMP/init-first.log"
        ( cd "$W" && ./init.sh > "$RUN_LOG" 2>&1 )
        RC=$?
        assert_eq "首次执行退出码" 0 "$RC"
        if [[ "$RC" -ne 0 ]]; then
            printf '         init.sh 完整输出（用于定位）:\n'
            sed 's/^/           /' "$RUN_LOG"
        fi

        if [[ -f "$W/.env" ]]; then
            ok ".env 已生成"
        else
            bad ".env 已生成" "存在" "缺失"
        fi

        PW_LEN="$(awk -F= '/^DB_PASSWORD=/{ print length($2) }' "$W/.env" 2>/dev/null)"
        assert_eq "密码长度" 16 "$PW_LEN"

        # 只有 .env 真的存在时才比较 sha，否则 "两个空 sha 相等" 会造成假通过
        if [[ -f "$W/.env" ]]; then
            H1="$(sha256sum "$W/.env" 2>/dev/null | cut -d' ' -f1)"
            ( cd "$W" && ./init.sh >/dev/null 2>&1 ); assert_eq "二次执行退出码" 0 "$?"
            H2="$(sha256sum "$W/.env" 2>/dev/null | cut -d' ' -f1)"
            assert_eq "二次执行不改 .env" "$H1" "$H2"
        else
            bad "二次执行退出码" "0" "首次未生成 .env，无法进入二次执行"
            bad "二次执行不改 .env" "文件存在且 sha 不变" ".env 不存在，无从比较"
        fi

        ( cd "$W" && ./init.sh --help >/dev/null 2>&1 ); assert_eq "--help 退出码" 0 "$?"
        ( cd "$W" && ./init.sh --bogus >/dev/null 2>&1 ); assert_eq "未知参数退出码" 2 "$?"
    fi
fi

# ------------------------------------------------------------ M2 analyze.sh
if want m2 || want all; then
    printf '\n=== M2 analyze.sh ===\n'
    LOG="tests/fixtures/tiny.log"

    if [[ ! -f "$LOG" ]]; then
        bad "测试样本存在" "tests/fixtures/tiny.log" "缺失"
    else
        OUT="$TMP/m2"
        mkdir -p "$OUT"

        ./analyze.sh --help >/dev/null 2>&1; assert_eq "--help 退出码" 0 "$?"
        ./analyze.sh >/dev/null 2>&1; assert_eq "缺 --log 退出码" 2 "$?"
        ./analyze.sh --log "$LOG" --top 0 --out "$OUT" >/dev/null 2>&1; assert_eq "--top 0 退出码" 2 "$?"
        ./analyze.sh --log "$LOG" --top abc --out "$OUT" >/dev/null 2>&1; assert_eq "--top 非数字退出码" 2 "$?"
        ./analyze.sh --log "$TMP/nope.log" --out "$OUT" >/dev/null 2>&1; assert_eq "文件不存在退出码" 1 "$?"

        ./analyze.sh --log "$LOG" --top 10 --out "$OUT" >/dev/null 2>&1; assert_eq "正常分析退出码" 0 "$?"

        CSV="$OUT/summary.csv"
        assert_eq "总请求数" 8 "$(csv_val "$CSV" total_requests)"
        assert_eq "独立 IP" 5 "$(csv_val "$CSV" unique_ips)"
        assert_eq "TOP1 URL" "/a" "$(csv_val "$CSV" top_url | tr -d '"')"
        assert_eq "TOP1 次数" 4 "$(csv_val "$CSV" top_url_count)"
        assert_eq "2xx 次数" 3 "$(csv_val "$CSV" status_2xx)"
        assert_eq "3xx 次数" 1 "$(csv_val "$CSV" status_3xx)"
        assert_eq "4xx 次数" 1 "$(csv_val "$CSV" status_4xx)"
        assert_eq "5xx 次数" 3 "$(csv_val "$CSV" status_5xx)"
        assert_eq "峰值小时" 10 "$(csv_val "$CSV" peak_hour)"
        assert_eq "峰值次数" 3 "$(csv_val "$CSV" peak_hour_count)"
        assert_eq "无法解析行" 0 "$(csv_val "$CSV" unparsed_lines)"

        if [[ -f "$OUT/report.md" ]]; then
            ok "report.md 已生成"
        else
            bad "report.md 已生成" "存在" "缺失"
        fi
        assert_eq "report 5xx 明细条数" 3 "$(awk '/## 4 5xx/,/## 5 /' "$OUT/report.md" 2>/dev/null | grep -c '^| `')"
        assert_eq "report TOP 表行数" 5 "$(awk '/## 2 TOP/,/## 3 状态码/' "$OUT/report.md" 2>/dev/null | grep -c '^| [0-9]')"
        assert_eq "report 小时行数" 4 "$(awk '/## 5 按小时/,0' "$OUT/report.md" 2>/dev/null | grep -c '^| [0-9][0-9]:00')"

        # .gz 输入必须与明文结果完全一致（summary.csv 不含路径信息，可比整文件）
        gzip -c "$LOG" > "$TMP/tiny.log.gz"
        OUT_GZ="$TMP/m2gz"; mkdir -p "$OUT_GZ"
        ./analyze.sh --log "$TMP/tiny.log.gz" --out "$OUT_GZ" >/dev/null 2>&1
        assert_eq ".gz 退出码" 0 "$?"
        assert_eq ".gz 总请求数" 8 "$(csv_val "$OUT_GZ/summary.csv" total_requests)"
        assert_eq ".gz 独立 IP" 5 "$(csv_val "$OUT_GZ/summary.csv" unique_ips)"
        assert_eq ".gz 与明文 summary 完全一致" "" "$(diff "$CSV" "$OUT_GZ/summary.csv" 2>&1)"

        # 空日志不能崩，且各项为 0
        : > "$TMP/empty.log"
        OUT_E="$TMP/m2e"; mkdir -p "$OUT_E"
        ./analyze.sh --log "$TMP/empty.log" --out "$OUT_E" >/dev/null 2>&1
        assert_eq "空日志退出码" 0 "$?"
        assert_eq "空日志总请求数" 0 "$(csv_val "$OUT_E/summary.csv" total_requests)"
        assert_eq "空日志峰值小时" "-" "$(csv_val "$OUT_E/summary.csv" peak_hour)"

        # --top 生效
        OUT_T="$TMP/m2t"; mkdir -p "$OUT_T"
        ./analyze.sh --log "$LOG" --top 2 --out "$OUT_T" >/dev/null 2>&1
        assert_eq "--top 2 的 TOP 表行数" 2 "$(awk '/## 2 TOP/,/## 3 状态码/' "$OUT_T/report.md" 2>/dev/null | grep -c '^| [0-9]')"

        # 坏行不能污染统计，且要如实计数
        printf 'garbage line\n%s\n' "$(head -1 "$LOG")" > "$TMP/bad.log"
        OUT_B="$TMP/m2b"; mkdir -p "$OUT_B"
        ./analyze.sh --log "$TMP/bad.log" --out "$OUT_B" >/dev/null 2>&1
        assert_eq "坏行场景退出码" 0 "$?"
        assert_eq "坏行场景总请求数" 2 "$(csv_val "$OUT_B/summary.csv" total_requests)"
        assert_eq "坏行计数" 1 "$(csv_val "$OUT_B/summary.csv" unparsed_lines)"
    fi
fi

# ------------------------------------------------------------- M3 Dockerfile
if want m3; then
    printf '\n=== M3 Dockerfile ===\n'
    if ! docker info >/dev/null 2>&1; then
        skip "M3 全部用例（docker 守护进程不可用）"
    else
        IMG="logops-web:test"
        docker build -q -t "$IMG" . >/dev/null 2>&1
        assert_eq "docker build 退出码" 0 "$?"

        SIZE="$(docker images "$IMG" --format '{{.Size}}' 2>/dev/null)"
        case "$SIZE" in
            *GB*)
                bad "镜像体积" "<300MB" "$SIZE" ;;
            *MB*)
                if [[ "$(printf '%s' "$SIZE" | sed 's/MB//' | cut -d. -f1)" -lt 300 ]]; then
                    ok "镜像体积 $SIZE（< 300MB）"
                else
                    bad "镜像体积" "<300MB" "$SIZE"
                fi ;;
            *)
                ok "镜像体积 $SIZE" ;;
        esac

        C="logops-m3"
        docker rm -f "$C" >/dev/null 2>&1
        docker run -d --name "$C" -p 18099:8080 "$IMG" >/dev/null 2>&1
        assert_eq "容器启动退出码" 0 "$?"

        ST=""
        for _ in $(seq 1 20); do
            ST="$(docker inspect --format '{{.State.Health.Status}}' "$C" 2>/dev/null)"
            [[ "$ST" == "healthy" ]] && break
            sleep 1
        done
        assert_eq "健康状态" healthy "$ST"

        assert_eq "whoami 非 root" nginx "$(docker exec "$C" whoami 2>/dev/null)"

        if command -v curl >/dev/null 2>&1; then
            assert_eq "首页 HTTP 200" 200 "$(curl -sS -o /dev/null -w '%{http_code}' http://localhost:18099/ 2>/dev/null)"
            assert_eq "healthz 返回 ok" ok "$(curl -sS http://localhost:18099/healthz 2>/dev/null)"
            # 探活请求不得进入访问日志，否则 analyze 的访问量会虚增
            sleep 2
            assert_eq "日志中无 healthz" 0 "$(docker logs "$C" 2>&1 | grep -c healthz)"
        else
            skip "HTTP 与日志相关用例（缺少 curl）"
        fi

        docker rm -f "$C" >/dev/null 2>&1
    fi
fi

printf '\n----------------------------------------\n'
printf '结果: %d 通过, %d 失败, %d 跳过\n' "$PASS" "$FAIL" "$SKIP"
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
