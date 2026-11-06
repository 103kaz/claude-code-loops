#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck hooks/*.sh
fi
out=$(bash hooks/test-pre-push-review.sh 2>&1) || {
  printf '%s\n' "$out" | grep '^FAIL' >&2
  exit 1
}
