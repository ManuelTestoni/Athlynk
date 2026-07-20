#!/usr/bin/env bash
# Static analysis + unit/widget tests. Pass --integration to also run the
# end-to-end flow (needs a connected device/emulator).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ codegen"
dart run build_runner build --delete-conflicting-outputs

echo "▸ analyze"
flutter analyze

echo "▸ unit + widget tests"
flutter test

if [[ "${1:-}" == "--integration" ]]; then
  echo "▸ integration test (athlete flow)"
  flutter test integration_test/athlete_flow_test.dart --flavor athlete
fi
