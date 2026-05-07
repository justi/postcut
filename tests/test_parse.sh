#!/usr/bin/env bash
# Tests for parse_gemfile_lock + parse_gemfile.
# Covers two regression scenarios:
#   - multi-platform gem dedup in Gemfile.lock
#   - gemspec-sourced direct deps (gem source repos like wpscan)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/adapters/ruby/parse.sh"

FIXTURES="$ROOT/tests/fixtures"
failed=0
ran=0

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"

  ran=$((ran + 1))
  if [ "$expected" = "$actual" ]; then
    printf 'ok    %-50s\n' "$desc"
  else
    printf 'FAIL  %-50s\n' "$desc"
    printf '       expected: %s\n' "$expected"
    printf '       actual:   %s\n' "$actual"
    failed=$((failed + 1))
  fi
}

# --- parse_gemfile_lock: multi-platform dedup ---

mp_lockfile="$FIXTURES/multi-platform/Gemfile.lock"
mp_count_total=$(parse_gemfile_lock "$mp_lockfile" | wc -l | tr -d ' ')
mp_count_sqlite3=$(parse_gemfile_lock "$mp_lockfile" | awk '$1 == "sqlite3"' | wc -l | tr -d ' ')
mp_count_thruster=$(parse_gemfile_lock "$mp_lockfile" | awk '$1 == "thruster"' | wc -l | tr -d ' ')

assert_eq "multi-platform: 3 unique gems total"  "3" "$mp_count_total"
assert_eq "multi-platform: sqlite3 dedup to 1"   "1" "$mp_count_sqlite3"
assert_eq "multi-platform: thruster dedup to 1"  "1" "$mp_count_thruster"

# --- parse_gemfile: explicit gem entries ---

direct_blazer=$(parse_gemfile "$FIXTURES/blazer-only/Gemfile" 2>/dev/null || true)
# blazer-only has no Gemfile, parse_gemfile returns 0 silently
assert_eq "no Gemfile: empty output"  ""  "$direct_blazer"

# --- parse_gemfile: gemspec-sourced (the wpscan case) ---

gs_dir="$FIXTURES/gemspec-source"
gs_deps=$(parse_gemfile "$gs_dir/Gemfile")
gs_count=$(printf '%s\n' "$gs_deps" | wc -l | tr -d ' ')

assert_eq "gemspec: 5 unique deps from .gemspec"  "5"  "$gs_count"
assert_eq "gemspec: addressable present"          "addressable"  "$(printf '%s\n' "$gs_deps" | grep '^addressable$')"
assert_eq "gemspec: json present"                 "json"         "$(printf '%s\n' "$gs_deps" | grep '^json$')"
assert_eq "gemspec: rake (add_dependency) present" "rake"        "$(printf '%s\n' "$gs_deps" | grep '^rake$')"
assert_eq "gemspec: rspec (dev) present"          "rspec"        "$(printf '%s\n' "$gs_deps" | grep '^rspec$')"
assert_eq "gemspec: minitest (parens form) present" "minitest"   "$(printf '%s\n' "$gs_deps" | grep '^minitest$')"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
