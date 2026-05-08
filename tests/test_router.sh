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

# Mock adapter pair. Function names use plain identifiers (no hyphens) —
# bash POSIX-form function names cannot contain '-'.
mockyes_local_metadata()      { printf 'LOCAL:%s\n' "$1"; }
mockyes_local_notes()         { :; }    # always empty → fall through
mockyes_local_advisories()    { printf 'LOCAL_ADV:%s\n' "$1"; }
mockyes_http_metadata()       { printf 'HTTP:%s\n' "$1"; }
mockyes_http_notes()          { printf 'HTTP_NOTES:%s\n' "$1"; }
mockyes_http_advisories()     { printf 'HTTP_ADV:%s\n' "$1"; }

mockno_local_metadata()       { printf 'LOCAL_NEVER:%s\n' "$1"; }
mockno_http_metadata()        { printf 'HTTP:%s\n' "$1"; }
mockno_http_notes()           { printf 'HTTP_NOTES:%s\n' "$1"; }
mockno_http_advisories()      { printf 'HTTP_ADV:%s\n' "$1"; }

# Override toolchain detection — only "mockyes" is treated as installed.
_postcut_toolchain_available() { [ "$1" = "mockyes" ]; }

# 1. Toolchain present + local returns something → uses local
assert_eq "local hit when toolchain available" \
  "LOCAL:foo" \
  "$(dispatch metadata mockyes foo)"

# 2. Toolchain present + local returns empty → falls through to HTTP
assert_eq "local empty falls through to HTTP" \
  "HTTP_NOTES:foo" \
  "$(dispatch notes mockyes foo)"

# 3. Local advisories populated → use it
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
