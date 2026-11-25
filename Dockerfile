# logops web 服务镜像
#
# 选 alpine 而不是 Debian 版的两个理由：
#   1. alpine 自带 busybox wget，healthcheck 不需要额外装包；
#      nginx:latest（Debian）既没有 curl 也没有 wget（见 docs/risks.md R13）
#   2. 体积约 50MB，离课程 300MB 上限很远
#
# 非 root 的三处配套改动（见 conf/nginx.conf 顶部注释）：
#   listen 8080、pid 放 /tmp、temp_path 放 /tmp

FROM nginx:1.27-alpine

LABEL org.opencontainers.image.title="logops-web" \
      org.opencontainers.image.description="logops 日志分析服务的展示层"

COPY conf/nginx.conf /etc/nginx/nginx.conf

# 首页给 healthcheck 一个稳定目标，也方便人工确认"服务真的在跑"
RUN printf '%s\n' \
      '<!doctype html>' \
      '<html lang="zh-CN"><head><meta charset="utf-8"><title>logops</title></head>' \
      '<body><h1>logops 日志分析服务</h1>' \
      '<p>服务状态：运行中</p>' \
      '<p><a href="/report/">查看分析报告</a></p></body></html>' \
      > /usr/share/nginx/html/index.html

# 非 root 需要的属主：静态目录与缓存目录。
# 注意：官方 nginx 镜像里 /var/log/nginx/access.log 是指向 /dev/stdout 的符号链接，
# 不挂载时日志只进 docker logs；落盘到 data/logs 依赖 compose 挂载覆盖该目录（见 risks.md R11）
RUN mkdir -p /var/log/nginx /var/cache/nginx \
 && chown -R nginx:nginx /var/cache/nginx /usr/share/nginx/html

USER nginx

EXPOSE 8080

# 打 /healthz（该 location 已关日志），避免探活请求污染访问统计
# 用 alpine 自带的 busybox wget，镜像里没有 curl
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
