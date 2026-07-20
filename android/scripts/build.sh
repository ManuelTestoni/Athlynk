#!/usr/bin/env bash
# Build both apps.
# Usage: ./scripts/build.sh [debug|release] [apk|appbundle] [dev|prod]
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-debug}"          # debug | release
TARGET="${2:-apk}"          # apk | appbundle
ENV="${3:-prod}"            # dev | prod

echo "▸ codegen (freezed / json_serializable)"
dart run build_runner build --delete-conflicting-outputs

for FLAVOR in athlete coach; do
  echo "▸ building ${FLAVOR} (${MODE}, ${TARGET}, ${ENV})"
  flutter build "${TARGET}" \
    --"${MODE}" \
    --flavor "${FLAVOR}" \
    -t "lib/main_${FLAVOR}.dart" \
    --dart-define-from-file="env/${ENV}.json"
done

echo "▸ artifacts:"
find build/app/outputs -name "*.apk" -o -name "*.aab" | sort
