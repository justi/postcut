#!/usr/bin/env bash
# Verifies dispatch() behavior: prefer local when available, fall back to HTTP
# silently when local returns empty, skip local entirely when toolchain absent.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core/router.sh"

failed=0
ran=0

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  ran=$((ran + 1))
  if [ "$expected" = "$actual" ]; then
    printf 'ok    %-55s\n' "$desc"
  else
    printf 'FAIL  %-55s\n' "$desc"
    printf '       expected: %s\n' "$expected"
    printf '       actual:   %s\n' "$actual"
    failed=$((failed + 1))
  fi
}

# --- mock adapter ---
mock_local_metadata()      { printf 'LOCAL:%s\n' "$1"; }
mock_local_notes()         { :; }                       # always empty
mock_local_advisories()    { printf 'LOCAL_ADV:%s\n' "$1"; }
mock_http_metadata()       { printf 'HTTP:%s\n' "$1"; }
mock_http_notes()          { printf 'HTTP_NOTES:%s\n' "$1"; }
mock_http_advisories()     { printf 'HTTP_ADV:%s\n' "$1"; }

# Override toolchain detection for the mock adapter.
_postcut_toolchain_available() { [ "$1" = "mockyes" ]; }

# Adapter "mock" needs a real toolchain key; we'll switch via _postcut_toolchain_available.
# Use mockyes / mockno variants by aliasing function names.

mockyes_local_metadata()      { mock_local_metadata "$@"; }
mockyes_local_notes()         { mock_local_notes "$@"; }
mockyes_local_advisories()    { mock_local_advisories "$@"; }
mockyes_http_metadata()       { mock_http_metadata "$@"; }
mockyes_http_notes()          { mock_http_notes "$@"; }
mockyes_http_advisories()     { mock_http_advisories "$@"; }

mockno_http_metadata()        { mock_http_metadata "$@"; }
mockno_http_notes()           { mock_http_notes "$@"; }
mockno_local_metadata()       { mock_local_metadata "$@"; }
mockno_http_advisories()      { mock_http_advisories "$@"; }

# --- tests ---

# 1. Toolchain present + local returns something → uses local
assert_eq "local hit when toolchain available" \
  "LOCAL:foo" \
  "$(dispatch metadata mockyes foo)"

# 2. Toolchain present + local returns empty → falls through to HTTP
assert_eq "local empty falls through to HTTP" \
  "HTTP_NOTES:foo" \
  "$(dispatch notes mockyes foo)"

# 3. Toolchain present + local function exists, HTTP also there, advisories
assert_eq "advisories prefers local when populated" \
  "LOCAL_ADV:foo" \
  "$(dispatch advisories mockyes foo)"

# 4. Toolchain absent → HTTP only, even if local function exists
assert_eq "no toolchain ⇒ HTTP only" \
  "HTTP:foo" \
  "$(dispatch metadata mockno foo)"

# 5. Unknown kind / function not declared → empty (no crash)
assert_eq "unknown kind returns empty" \
  "" \
  "$(dispatch nonsense mockyes foo)"

# 6. Unknown adapter → empty
assert_eq "unknown adapter returns empty" \
  "" \
  "$(dispatch metadata bogusadapter foo)"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
