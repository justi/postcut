#!/usr/bin/env bash
# Tests for parse_changelog_content — the shared markdown CHANGELOG parser
# used by both fetch_changelog_md (HTTP) and any future local readers.
# Covers:
#   - Keep-a-Changelog headers (## 1.2.3 / ## [1.2.3])
#   - Plain headers (## 1.2.3 (date))
#   - Rails-style headers (## Rails 8.1.3 (March 24, 2026) ##)
#   - "No changes." trivial bullet filter
#   - Sub-headers inside a version section don't reset state

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core/github.sh"

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
    printf '       in: %s\n' "$haystack"
    failed=$((failed + 1))
  fi
}

check_not() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  ran=$((ran + 1))
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    printf 'FAIL  %-55s\n' "$desc"
    printf '       unexpected substring: %s\n' "$needle"
    printf '       in: %s\n' "$haystack"
    failed=$((failed + 1))
  else
    printf 'ok    %-55s\n' "$desc"
  fi
}

# --- Rails-style "## Rails X.Y.Z (date) ##" header ---

rails_changelog="## Rails 8.1.3 (March 24, 2026) ##

*   Fix JSONGemCoderEncoder to correctly serialize custom object hash keys.
*   Fix inflections to better handle overlapping acronyms.

## Rails 8.1.2.1 (March 23, 2026) ##

*   No changes.

## Rails 8.1.2 (January 08, 2026) ##

*   Add config.action_controller.live_streaming_excluded_keys.
*   Fix IpSpoofAttackError message."

out=$(parse_changelog_content "$rails_changelog" "8.1.3,8.1.2.1,8.1.2")
check "Rails-style: 8.1.3 bullets present"   "8.1.3: Fix JSONGemCoderEncoder"  "$out"
check "Rails-style: 8.1.2 bullets present"   "8.1.2: Add config"               "$out"
check_not "Rails-style: 8.1.2.1 'No changes.' filtered"  "8.1.2.1:"  "$out"

# --- Keep-a-Changelog with [version] - date ---

kac="## [1.2.3] - 2024-01-15

- Fix bug A
- Add feature B

## [1.2.2] - 2024-01-10

- Patch X"

out=$(parse_changelog_content "$kac" "1.2.3,1.2.2")
check "KaC: bracketed version 1.2.3 matched"  "1.2.3: Fix bug A"  "$out"
check "KaC: bracketed version 1.2.2 matched"  "1.2.2: Patch X"    "$out"

# --- Sub-header inside version section doesn't reset ---

with_subheaders="## 2.0.0 (2024-06-01)

### Active Record

* Add migration support

### Active Model

* New validators"

out=$(parse_changelog_content "$with_subheaders" "2.0.0")
check "sub-headers don't reset section"  "2.0.0:"  "$out"
check "first bullet collected past sub-header" "Add migration support"  "$out"

# --- 'No changes' variants are filtered ---

trivial_only="## 3.0.0 (2024-01-01)

* No changes.

## 3.0.1 (2024-01-02)

* No changes

## 3.0.2 (2024-01-03)

* Real fix here"

out=$(parse_changelog_content "$trivial_only" "3.0.0,3.0.1,3.0.2")
check_not "'No changes.' filtered (3.0.0)"  "3.0.0:"  "$out"
check_not "'No changes' filtered (3.0.1)"   "3.0.1:"  "$out"
check     "real bullet survives (3.0.2)"    "3.0.2: Real fix here"  "$out"

# --- Empty input is empty output ---

out=$(parse_changelog_content "" "1.0.0")
check_not "empty input → empty output"  ":"  "$out"

# --- No matching versions → empty ---

out=$(parse_changelog_content "$kac" "9.9.9")
check_not "non-matching version → empty"  ":"  "$out"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
