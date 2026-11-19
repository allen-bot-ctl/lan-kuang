#!/usr/bin/env bash
# C3/C4/C5：带隐藏参数启动应用打开面板，应用打印截图区域（左上原点、点）与 backingScaleFactor；
# screencapture -R 按点裁剪，输出像素 = 点 × scale。再检查裁剪图不是全黑、面板布局自检通过。
set -euo pipefail
cd "$(dirname "$0")/.."
source ./project.env
bin="build/${NAME}.app/Contents/MacOS/$NAME"
mkdir -p shots

nonblack() {  # 打印非黑像素占比；全黑返回 1
  local png="$1" bmp="/tmp/$(basename "$1").bmp"
  sips -s format bmp "$png" --out "$bmp" >/dev/null
  python3 - "$bmp" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
off = struct.unpack_from('<I', d, 10)[0]
w, h = struct.unpack_from('<ii', d, 18)
bpp = struct.unpack_from('<H', d, 28)[0]
step = bpp // 8
row = ((w * bpp + 31) // 32) * 4
n = lit = mx = 0
for y in range(abs(h)):
    base = off + y * row
    for x in range(w):
        p = base + x * step
        v = max(d[p], d[p + 1], d[p + 2])
        mx = max(mx, v); n += 1
        if v > 16: lit += 1
print(f"{sys.argv[1]}: {w}x{abs(h)} max={mx} lit={lit/n:.3f}")
sys.exit(0 if mx > 0 and lit > 0.01 else 1)
PY
}

shoot() {  # $1=后缀  其余=启动参数
  local tag="$1"; shift
  local log="/tmp/shots-$tag.log"
  "$bin" "$@" >"$log" 2>&1 &
  local pid=$!
  sleep 6
  cat "$log"
  local mb pn it w
  mb=$(awk '/^DEBUG_RECT_MENUBAR/{print $2}' "$log")
  it=$(awk '/^DEBUG_RECT_ITEM/{print $2}' "$log")
  w=$(awk '/^DEBUG_ITEM_WIDTH/{print $2}' "$log")
  awk -v w="$w" 'BEGIN{exit !(w != "" && w+0 > 0 && w+0 <= 46)}' || { kill -TERM "$pid" || true; echo "::error::菜单栏项宽 ${w}pt 超过 46pt"; return 1; }
  echo "RELEASE: item_width${tag}=${w}pt"
  pn=$(awk '/^DEBUG_RECT_PANEL/{print $2}' "$log")
  [ -n "$mb" ] && [ -n "$pn" ] || { kill -TERM "$pid" || true; echo "::error::应用没有输出截图区域"; return 1; }
  screencapture -x "shots/full$tag.png"
  screencapture -x -R"$mb" "shots/menubar$tag.png"
  screencapture -x -R"$it" "shots/item$tag.png"
  screencapture -x -R"$pn" "shots/panel$tag.png"
  kill -TERM "$pid" 2>/dev/null || true; sleep 1; kill -KILL "$pid" 2>/dev/null || true
  for f in "shots/menubar$tag.png" "shots/panel$tag.png" "shots/item$tag.png"; do
    sips -g pixelWidth -g pixelHeight "$f" | tr '\n' ' '; echo
    nonblack "$f" || { echo "::error::$f 全黑"; return 1; }
  done
  grep -q "^DEBUG_LAYOUT .* ok=true" "$log" || { echo "::error::面板布局自检失败"; return 1; }
}

"$bin" --debug-render-icons="$PWD/shots" | tee /tmp/shots-icons.log; grep DEBUG_FONT /tmp/shots-icons.log | sed "s/^/RELEASE: /"
ls shots/icon2x-*.png | wc -l | awk '{exit !($1==5)}' || { echo "::error::2x 图标没有渲染满 5 张"; exit 1; }
for f in shots/icon[12]x-*.png; do sips -g pixelWidth -g pixelHeight "$f" | tr '\n' ' '; echo; done
shoot "" --debug-open-panel
shoot "-longest" --debug-open-panel --debug-longest --debug-battery=ac,100
for st in ac,100 charging,18 battery,62 battery,15 none; do
  shoot "-bat-${st%%,*}-${st#*,}" --debug-open-panel --debug-battery="$st"
done
grep -h "^DEBUG_" /tmp/shots-*.log | sed 's/^/RELEASE: /'
ls -l shots
