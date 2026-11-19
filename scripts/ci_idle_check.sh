#!/usr/bin/env bash
# C6：arm64 原生启动，面板关闭空闲 60 秒，每 5 秒采样 ps rss/%cpu。
# 输出 RELEASE: rss=<MB>MB cpu=<avg%>；RSS 峰值 > 60MB 或 CPU 均值 > 0.5% 失败。
set -euo pipefail
cd "$(dirname "$0")/.."
source ./project.env
bin="build/${NAME}.app/Contents/MacOS/$NAME"
MAX_RSS_MB="${MAX_RSS_MB:-60}"
MAX_CPU="${MAX_CPU:-0.5}"

arch -arm64 "$bin" >/tmp/idle.log 2>&1 &
pid=$!
cleanup() { kill -TERM "$pid" 2>/dev/null || true; sleep 1; kill -KILL "$pid" 2>/dev/null || true; }
trap cleanup EXIT
sleep 5   # 启动预热不计入
samples=() ; rss_max=0
for i in $(seq 1 12); do
  sleep 5
  kill -0 "$pid" 2>/dev/null || { echo "::error::进程在空闲测量中退出"; cat /tmp/idle.log; exit 1; }
  read -r rss cpu < <(ps -o rss=,%cpu= -p "$pid")
  echo "sample $i: rss=${rss}KB cpu=${cpu}%"
  samples+=("$cpu")
  (( rss > rss_max )) && rss_max=$rss
done
rss_mb=$(awk -v k="$rss_max" 'BEGIN{printf "%.1f", k/1024}')
cpu_avg=$(printf '%s\n' "${samples[@]}" | awk '{s+=$1} END{printf "%.2f", s/NR}')
echo "RELEASE: rss=${rss_mb}MB cpu=${cpu_avg}%"
awk -v r="$rss_mb" -v m="$MAX_RSS_MB" 'BEGIN{exit !(r<=m)}' || { echo "::error::RSS ${rss_mb}MB > ${MAX_RSS_MB}MB"; exit 1; }
awk -v c="$cpu_avg" -v m="$MAX_CPU" 'BEGIN{exit !(c<=m)}' || { echo "::error::CPU ${cpu_avg}% > ${MAX_CPU}%"; exit 1; }
