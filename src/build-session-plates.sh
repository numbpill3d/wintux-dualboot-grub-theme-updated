#! /usr/bin/env bash
# Build the session-choice plates (2350x1020, same canvas as the stock WinTux
# templates) from the original WinTux hand renders plus the Sway and KDE Plasma
# marks.  The output feeds build-sessions.sh, which rescales them for the
# target screen exactly the way build.sh rescales the stock templates.
#
#   src/build-session-plates.sh <out_dir>
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/image_templates"
MARKS="$HERE/marks"
OUT="${1:?usage: build-session-plates.sh <out_dir>}"

W=2350; H=1020
DIM=0.15           # the stock power.png / efi.png plates use 0.203; a touch
                   # darker keeps Tux and the Windows flag as background
                   # texture rather than as content
PAD=200            # canvas margin, room for the bloom
LX=540; RX=1740    # centre of the left / right hand
CY=470

mkdir -p "$OUT"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
magick "$SRC/background.png" +repage -evaluate multiply $DIM "$T/dim.png"

# emblem <svg> <long edge px> <bloom alpha> <out.png>
emblem() {
  local svg="$1" size="$2" bloom="$3" out="$4"
  magick -background none "$svg" -resize "${size}x${size}" -trim +repage \
         -bordercolor none -border $PAD "$T/m.png"
  magick "$T/m.png" -alpha extract -blur 0x42 -level 0%,62% "$T/mask.png"
  magick "$T/mask.png" -fill '#ff9a3c' -colorize 100 "$T/tint.png"
  magick "$T/tint.png" "$T/mask.png" -alpha off -compose CopyOpacity -composite \
         -channel A -evaluate multiply "$bloom" +channel "$T/glow.png"
  magick "$T/glow.png" "$T/m.png" -compose over -composite "$out"
}

# halo <cx> <cy> <brightness> <out> - the soft pool of light under the emblem,
# in the same key as the stock power.png plate
halo() {
  local cx="$1" cy="$2" bright="$3" out="$4" r=620
  magick -size $((r*2))x$((r*2)) radial-gradient:'#b03c0a-#000000' \
         -evaluate pow 2.6 -evaluate multiply "$bright" "$T/g.png"
  magick -size ${W}x${H} xc:black "$T/g.png" \
         -geometry "+$((cx-r))+$((cy-r))" -compose plus -composite "$out"
}

# plate <svg> <cx> <size> <bloom> <halo brightness> <out>
plate() {
  local svg="$1" cx="$2" size="$3" bloom="$4" bright="$5" out="$6"
  emblem "$svg" "$size" "$bloom" "$T/e.png"
  halo "$cx" "$CY" "$bright" "$T/h.png"
  local w h
  w=$(identify -format "%w" "$T/e.png"); h=$(identify -format "%h" "$T/e.png")
  magick "$T/dim.png" "$T/h.png" -compose screen -composite \
         "$T/e.png" -geometry "+$((cx-w/2))+$((CY-h/2))" -compose over -composite \
         "$out"
}

# Plasma sits in the left hand and Sway in the right, so that arrowing down the
# menu moves the light from one hand to the other the way the stock
# linux/windows plates do.  The Plasma mark is sparse and thin, so it is drawn
# larger and lit harder than the dense Sway tree.
plate "$MARKS/plasma.svg" $LX 640 1.00 1.5 "$OUT/plasma.png"
plate "$MARKS/sway.svg"   $RX 620 0.68 1.0 "$OUT/sway.png"
