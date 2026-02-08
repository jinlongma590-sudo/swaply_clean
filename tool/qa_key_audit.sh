#!/usr/bin/env bash
set -euo pipefail

: "${QA_EMAIL:?QA_EMAIL is required}"
: "${QA_PASS:?QA_PASS is required}"

flutter test integration_test/key_audit_test.dart \
  --dart-define=QA_MODE=true \
  --dart-define=QA_EMAIL="$QA_EMAIL" \
  --dart-define=QA_PASS="$QA_PASS" \
  -d emulator-5554 \
  --no-pub \
  --timeout 10m \
  -r expanded