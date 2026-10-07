#!/bin/bash
# Drags the map on munimmapsexample://layer/<library>/<pan mode> and saves raw
# frames during the drag, for layer-probe.py. Android phone on USB.
#   layer-pan.sh <rnmapbox|rnmaps-google> <pan|pan45|pan45pad> <out dir> [frames] [drag ms]
set -e
library=$1 mode=$2 out=$3 frames=${4:-6} ms=${5:-5000}
mkdir -p "$out"
name="$library-${mode//\//-}"
adb shell am force-stop com.munimtech.munimmapsexample
adb shell am start -a android.intent.action.VIEW -d "munimmapsexample://layer/$library/$mode" com.munimtech.munimmapsexample >/dev/null
sleep 12
adb exec-out screencap -p > "$out/$name-still.png"
adb exec-out screencap > "$out/$name-still.raw"
# A diagonal drag (5 s unless given), with frames taken while the finger moves.
adb shell input swipe 380 1500 700 900 "$ms" &
swipe=$!
sleep 0.3
for i in $(seq 1 "$frames"); do
  adb exec-out screencap > "$out/$name-drag$i.raw"
done
wait $swipe
adb exec-out screencap -p > "$out/$name-after.png"
adb exec-out screencap > "$out/$name-after.raw"
