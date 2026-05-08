#!/usr/bin/env bash
# Tests for fetch_ruby_delta header formatting. Mocks curl + dispatch so
# the function exercises only the rubygems versions parsing path.
#
# Specifically guards against the empty-leading-field bug: when a gem was
# introduced post-cutoff, $pre.number is null and the jq output starts
# with a delimiter. With a whitespace delimiter (tab) bash strips it and
# every field shifts; with `|` the empty field is preserved.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core/router.sh"
source "$ROOT/lib/core/github.sh"
source "$ROOT/lib/adapters/ruby/local.sh"
source "$ROOT/lib/adapters/ruby/fetch.sh"

# Mock curl: returns canned JSON per gem name; fails otherwise so any
# accidental network call is visible.
curl() {
  case "$*" in
    *"minitest-mock.json"*)
      printf '%s' '[{"number":"5.27.0","created_at":"2025-12-18T00:00:00Z","prerelease":false,"platform":"ruby"}]'
      return 0
      ;;
    *"normal_gem.json"*)
      printf '%s' '[
        {"number":"1.0.0","created_at":"2025-01-01T00:00:00Z","prerelease":false,"platform":"ruby"},
        {"number":"2.0.0","created_at":"2025-12-01T00:00:00Z","prerelease":false,"platform":"ruby"}
      ]'
      return 0
      ;;
    *"old_gem.json"*)
      printf '%s' '[{"number":"1.0.0","created_at":"2024-01-01T00:00:00Z","prerelease":false,"platform":"ruby"}]'
      return 0
      ;;
  esac
  return 1
}
export -f curl

# Mock dispatcher: short-circuits notes/metadata/advisories so the test
# isolates header formatting (the layer where the bug lived).
dispatch() {
  return 0
}
export -f dispatch

failed=0
ran=0

check_substr() {
  local desc="$1" needle="$2" haystack="$3"
  ran=$((ran + 1))
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    printf 'ok    %-60s\n' "$desc"
  else
    printf 'FAIL  %-60s\n' "$desc"
    printf '       expected substring: %s\n' "$needle"
    printf '       actual: %s\n' "$haystack"
    failed=$((failed + 1))
  fi
}

check_no_substr() {
  local desc="$1" needle="$2" haystack="$3"
  ran=$((ran + 1))
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    printf 'FAIL  %-60s\n' "$desc"
    printf '       did NOT expect: %s\n' "$needle"
    printf '       actual: %s\n' "$haystack"
    failed=$((failed + 1))
  else
    printf 'ok    %-60s\n' "$desc"
  fi
}

check_empty() {
  local desc="$1" out="$2"
  ran=$((ran + 1))
  if [ -z "$out" ]; then
    printf 'ok    %-60s\n' "$desc"
  else
    printf 'FAIL  %-60s\n' "$desc"
    printf '       expected empty, got: %s\n' "$out"
    failed=$((failed + 1))
  fi
}

# 1. Newly-introduced gem (only post-cutoff release, $pre.number is null)
out=$(fetch_ruby_delta minitest-mock 2025-09-01)
check_substr    "newly-introduced: header uses (introduced) label"   "(introduced)"            "$out"
check_substr    "newly-introduced: cur_v is the version, not a date" "→ 5.27.0 (current,"     "$out"
check_substr    "newly-introduced: cur_date is the date"             "(current, 2025-12-18)"   "$out"
check_no_substr "newly-introduced: no field-shift artifact"          "→ 2025-12-18 (current," "$out"

# 2. Normal upgrade case (pre + post both present)
out=$(fetch_ruby_delta normal_gem 2025-09-01)
check_substr "normal upgrade: pre version present"     "1.0.0 (last seen)"     "$out"
check_substr "normal upgrade: cur version present"     "→ 2.0.0 (current,"     "$out"
check_substr "normal upgrade: date present"            "(current, 2025-12-01)" "$out"

# 3. No post-cutoff releases
out=$(fetch_ruby_delta old_gem 2025-09-01)
check_empty "no post-cutoff: silent (no header)" "$out"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
