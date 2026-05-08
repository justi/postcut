#!/usr/bin/env bash
# Tests the --summary post-process filter that lives inline in bin/postcut.
# Builds a synthetic deltas string covering the cases we care about
# (security CVE bullets, breaking-change bullets, plain feature bullets,
# blank lines, multiple gem blocks) and pipes it through the same awk
# program the binary uses.

set -uo pipefail

# Mirror the awk program embedded in bin/postcut. Keep these two in
# sync — if you change the filter there, copy the change here.
filter() {
  awk '
    /^[^[:space:]]/ { print; next }
    /^[[:space:]]*$/ { print; next }
    /CVE-|GHSA-/ { print; next }
    /(^|[^[:alpha:]])([Ss]ecurity|[Bb]reaking|[Dd]eprecat(ed|ion|es|ing)?|CRITICAL|critical)([^[:alpha:]]|$)/ { print }
  '
}

deltas='rails: 8.0.2 (last seen) → 8.1.3 (current, 2026-03-24)
  [activerecord] 8.1.3: Fix insert_all log message; Restore previous instrumenter
  [actionpack] 8.0.2.1: GHSA-76r7-hhxj-r776 [medium] CVE-2025-55193: ANSI escape injection
  [actionview] 8.1.3: Fix encoding errors for non-ASCII string locals

puma: 6.6.1 (last seen) → 8.0.1 (current, 2026-04-26)
  7.0.0: Breaking changes; Set default max_keep_alive to 999
  7.0.4: Bugfixes; Fix SSL_shutdown error handling

bcrypt: 3.1.20 (last seen) → 3.1.22 (current, 2026-03-18)
  3.1.21: Routine maintenance update
  3.1.22: Drop support for Ruby 2.7 (deprecated)

substr-trap: 1.0.0 (last seen) → 1.1.0 (current, 2026-03-01)
  1.1.0: nonbreaking internal cleanup of cache layer
  1.1.0: indiscriminate logging cleanup
'

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
    failed=$((failed + 1))
  else
    printf 'ok    %-60s\n' "$desc"
  fi
}

filtered=$(printf '%s' "$deltas" | filter)

# Headers always retained (signal that the gem changed at all).
check_substr "header retained: rails"  "rails: 8.0.2"  "$filtered"
check_substr "header retained: puma"   "puma: 6.6.1"   "$filtered"
check_substr "header retained: bcrypt" "bcrypt: 3.1.20" "$filtered"

# Security bullets retained.
check_substr "kept: CVE bullet"  "CVE-2025-55193"        "$filtered"
check_substr "kept: GHSA bullet" "GHSA-76r7-hhxj-r776"   "$filtered"

# Breaking-change keyword retained.
check_substr "kept: 'Breaking changes' bullet" "Breaking changes" "$filtered"

# Deprecation keyword retained.
check_substr "kept: 'deprecated' bullet" "deprecated" "$filtered"

# Plain refactor / fix bullets dropped.
check_no_substr "dropped: routine maintenance"        "Routine maintenance"           "$filtered"
check_no_substr "dropped: 'Fix encoding' (no keyword)" "Fix encoding errors"          "$filtered"
check_no_substr "dropped: 'Fix insert_all' bullet"    "insert_all log message"        "$filtered"
check_no_substr "dropped: SSL_shutdown bugfix"        "SSL_shutdown error handling"   "$filtered"

# Word-boundary regression: substring matches must NOT trigger.
check_no_substr "word boundary: 'nonbreaking' does not match 'breaking'" "nonbreaking internal cleanup" "$filtered"
check_no_substr "word boundary: 'indiscriminate' does not match"          "indiscriminate logging"       "$filtered"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
