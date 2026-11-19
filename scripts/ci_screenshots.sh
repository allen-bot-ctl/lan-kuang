#!/usr/bin/env bash
# C4/C5：启动带 --debug-open-panel 的应用，截菜单栏与面板区域到 shots/。失败不阻断（由工作流 continue-on-error）。
set -euo pipefail
cd "$(dirname "$0")/.."
source ./project.env
bin="build/${NAME}.app/Contents/MacOS/$NAME"
mkdir -p shots
"$bin" --debug-open-panel >/tmp/shots.log 2>&1 &
pid=$!
trap 'kill -TERM "$pid" 2>/dev/null || true; sleep 1; kill -KILL "$pid" 2>/dev/null || true' EXIT
sleep 6
screencapture -x shots/full.png
W=$(sips -g pixelWidth shots/full.png | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight shots/full.png | awk '/pixelHeight/{print $2}')
echo "screen ${W}x${H}"
cw=$(( W < 1400 ? W : 1400 ))
sips -c 60 "$cw" --cropOffset 0 $((W-cw)) shots/full.png --out shots/menubar.png >/dev/null
ch=$(( H < 400 ? H : 400 ))
sips -c "$ch" "$cw" --cropOffset 0 $((W-cw)) shots/full.png --out shots/panel.png >/dev/null
ls -l shots
