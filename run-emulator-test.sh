#!/usr/bin/env bash
set -euo pipefail

mkdir -p emulator-results

# Always save emulator evidence, even when the test fails.
save_results() {
  adb logcat -d -v threadtime > emulator-results/logcat.txt 2>/dev/null || true
  adb shell dumpsys activity activities > emulator-results/activities.txt 2>/dev/null || true
  adb exec-out screencap -p > emulator-results/screen.png 2>/dev/null || true
  adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
  adb pull /sdcard/window.xml emulator-results/window.xml >/dev/null 2>&1 || true
}
trap save_results EXIT

adb wait-for-device

aapt="$(find "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}/build-tools" -type f -name aapt | sort -V | tail -n 1)"
[[ -n "$aapt" ]] || { echo 'Android aapt not found'; exit 1; }
package="$("$aapt" dump badging test-app.apk | awk -F "'" '/^package: name=/ { print $2; exit }')"
[[ -n "$package" ]] || { echo 'Unable to identify APK package name'; exit 1; }
echo "Testing Android package: $package"

# Most GitHub-hosted Android emulators use x86_64, not ARM64.
"$aapt" dump badging test-app.apk | grep -E '^native-code:' || true

adb logcat -c || true
if ! adb install -r test-app.apk 2>&1 | tee emulator-results/install.txt; then
  echo 'APK install failed. If it contains only arm64-v8a native libraries, add x86_64 to the emulator build.'
  exit 1
fi

adb shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 | tee emulator-results/launch.txt
sleep 12

if ! adb shell pidof "$package" >/dev/null 2>&1; then
  echo "App process not running after launch: $package"
  exit 1
fi

echo 'PASS: APK installed, launched, and was still running after 12 seconds.'

# Run project instrumented tests when the repository defines them.
if [[ "${SOURCE_BUILD:-false}" == true && -d app/src/androidTest ]]; then
  ./gradlew :app:connectedDebugAndroidTest --stacktrace
fi
