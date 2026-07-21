#!/usr/bin/env bash
# Run the coach app on a connected device/emulator.
# Usage: ./scripts/run_coach.sh [dev|prod] [extra flutter args…]
#
# Defaults to --release (AOT, shipped-build speed) — always runs as fast as it
# will on a real device. Override when you need to iterate on code:
#   ./scripts/run_coach.sh prod --debug     # JIT, hot reload, 3-10x slower
#   ./scripts/run_coach.sh prod --profile   # AOT + DevTools to measure fps
#
# On an emulator this also opts out of Impeller. Measured on the Pixel 8 AVD
# (arm64, gfxstream, macOS host): with Impeller the app rendered *zero* frames
# — the GLES backend stalls on the emulator's translated GPU and the app looks
# frozen. With Skia it holds ~40 fps. On real hardware Impeller is the faster
# backend, so this is emulator-only and never applies to a shipped build.
# Override by passing --enable-impeller explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."
ENV="${1:-prod}"; shift || true

# Plain string, not an array: macOS ships bash 3.2, where `"${arr[@]}"` on an
# empty array trips `set -u`.
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
IMPELLER=""
if [[ "$*" != *enable-impeller* ]] \
   && [[ -x "$ADB" ]] && "$ADB" devices | grep -q "^emulator-.*device$"; then
  IMPELLER="--no-enable-impeller"
  echo "▸ emulator detected — running with Skia ($IMPELLER)"
fi

# Default to release unless the caller already picked a build mode.
MODE="--release"
if [[ "$*" == *--debug* || "$*" == *--profile* || "$*" == *--release* ]]; then
  MODE=""
fi

exec flutter run \
  --flavor coach \
  -t lib/main_coach.dart \
  --dart-define-from-file="env/${ENV}.json" \
  ${MODE} \
  ${IMPELLER} \
  "$@"
