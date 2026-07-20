#!/usr/bin/env bash
# Run the coach app on a connected device/emulator.
# Usage: ./scripts/run_coach.sh [dev|prod] [extra flutter args…]
#
# Defaults to debug (JIT, asserts on) — fine for iterating, but 3-10x slower
# than the shipped build, so never judge frame rate from it. For that:
#   ./scripts/run_coach.sh prod --profile
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
  IMPELLER="--enable-impeller=false"
  echo "▸ emulator detected — running with Skia ($IMPELLER)"
fi

exec flutter run \
  --flavor coach \
  -t lib/main_coach.dart \
  --dart-define-from-file="env/${ENV}.json" \
  ${IMPELLER} \
  "$@"
