#!/usr/bin/env bash
# Smoke tests for ruby_local_metadata. Requires `gem` in PATH and at least
# one well-known gem installed (rails — most Ruby dev machines have it).
# If neither is available, the test reports "SKIP" and exits 0.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core/router.sh"
source "$ROOT/lib/core/github.sh"
source "$ROOT/lib/adapters/ruby/local.sh"

if ! command -v gem >/dev/null 2>&1; then
  echo "SKIP  no \`gem\` in PATH (test requires Ruby toolchain)"
  exit 0
fi
if ! gem specification rails >/dev/null 2>&1; then
  echo "SKIP  rails gem not installed locally (test target)"
  exit 0
fi

failed=0
ran=0

check() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  ran=$((ran + 1))
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    printf 'ok    %-55s\n' "$desc"
  else
    printf 'FAIL  %-55s\n' "$desc"
    printf '       expected substring: %s\n' "$needle"
    printf '       actual: %s\n' "$haystack"
    failed=$((failed + 1))
  fi
}

# 1. Metadata returns a github URL for rails (a gem with rich gemspec metadata).
out=$(ruby_local_metadata rails)
check "rails metadata: returns github URL"  "github.com/rails/rails"  "$out"

# 2. parse_github_repo_from_url turns the local-derived URL into "owner/repo".
parsed=$(parse_github_repo_from_url "$out")
check "rails metadata + parser: rails/rails"  "rails/rails"  "$parsed"

# 3. Unknown gem returns empty (no crash, no false output).
out=$(ruby_local_metadata this-gem-definitely-does-not-exist-xyz)
if [ -z "$out" ]; then
  printf 'ok    %-55s\n' "unknown gem returns empty"
  ran=$((ran + 1))
else
  printf 'FAIL  %-55s\n' "unknown gem returns empty"
  printf '       actual: %s\n' "$out"
  failed=$((failed + 1))
  ran=$((ran + 1))
fi

# 4. Empty arg → empty output (defensive).
out=$(ruby_local_metadata "")
if [ -z "$out" ]; then
  printf 'ok    %-55s\n' "empty arg returns empty"
  ran=$((ran + 1))
else
  printf 'FAIL  %-55s\n' "empty arg returns empty"
  failed=$((failed + 1))
  ran=$((ran + 1))
fi

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
