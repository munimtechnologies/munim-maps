#!/bin/bash
# Opens an example deep link on the Android phone (USB), waits for a log line
# and keeps the MUNIM_MAPS log and a screenshot.
#   run-check.sh <url> <regex of the last line> <out dir> <name>
#   run-check.sh munimmapsexample://layer/rnmapbox/check "LAYER_OVER summary" ./out rnmapbox
url=$1 done=$2 out=$3 name=$4
mkdir -p "$out"
adb logcat -c
adb shell am force-stop com.munimtech.munimmapsexample
adb shell am start -a android.intent.action.VIEW -d "$url" com.munimtech.munimmapsexample >/dev/null
for _ in $(seq 1 120); do
  if adb logcat -d -s ReactNativeJS:V AndroidRuntime:E | grep -qE "$done|FATAL"; then break; fi
  sleep 3
done
sleep 2
adb logcat -d -s ReactNativeJS:V AndroidRuntime:E | grep -E "MUNIM_MAPS|FATAL" > "$out/$name.log"
adb exec-out screencap -p > "$out/$name.png"
grep -E "$done|FATAL" "$out/$name.log" | sed -E 's/.*(MUNIM_MAPS)/\1/' | cut -c1-900
