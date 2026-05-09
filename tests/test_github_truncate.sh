#!/usr/bin/env bash
# Tests for _truncate_safe and the integrated _parse_changelog_content
# truncation behaviour. Regression coverage for issue #11 — without
# link-aware truncation, the 140-char cut lands inside `[label](url)`
# and produces broken markdown.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core/github.sh"

failed=0
ran=0

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  ran=$((ran + 1))
  if [ "$expected" = "$actual" ]; then
    printf 'ok    %-60s\n' "$desc"
  else
    printf 'FAIL  %-60s\n' "$desc"
    printf '       expected: %s\n' "$expected"
    printf '       actual:   %s\n' "$actual"
    failed=$((failed + 1))
  fi
}

check_no_substr() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
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

check_substr() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
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

# ---- 1. _truncate_safe direct unit tests ----

# Short string passes through unchanged.
out=$(_truncate_safe "short text" 140)
assert_eq "short string unchanged" "short text" "$out"

# Long string with no markdown gets a plain cut.
long="$(printf 'a%.0s' {1..200})"
out=$(_truncate_safe "$long" 140)
assert_eq "plain long string truncated to 140" "140" "${#out}"

# Cut landing mid-URL strips the unclosed `[label](url`.
# Build: 130 chars of padding + " [label](http://example.com/path)" — but
# pin the cut so the closing `)` lands past 140.
pad="$(printf 'p%.0s' {1..118})"
input="${pad} [label](http://example.com/long-url)"
out=$(_truncate_safe "$input" 140)
check_no_substr "mid-URL cut: no leftover [label]( prefix" "[label](" "$out"
check_no_substr "mid-URL cut: no half-URL fragment"        "http://example" "$out"

# Cut landing mid-label strips the unclosed `[partial`.
input2="${pad} [partial-label-text-that-is-very-long"
out=$(_truncate_safe "$input2" 140)
check_no_substr "mid-label cut: no leftover [partial prefix" "[partial" "$out"

# Complete link kept intact when it ends before the cap.
input3="leading text [done](http://x.test/y) tail filler $(printf 'z%.0s' {1..80})"
out=$(_truncate_safe "$input3" 140)
check_substr "complete link preserved" "[done](http://x.test/y)" "$out"

# Boundary: exact-cap input passes through untouched.
exact="$(printf 'a%.0s' {1..140})"
out=$(_truncate_safe "$exact" 140)
assert_eq "exact 140 chars: no truncation" "$exact" "$out"

# Boundary: empty input is a no-op.
out=$(_truncate_safe "" 140)
assert_eq "empty input: empty output" "" "$out"

# ---- 2. _parse_changelog_content integration ----

# Use a real fixture so the heredoc parens don't fight bash's parser.
# The first 3.20.1 bullet's URL stretches past char 140 — without
# link-aware truncation the cut would land mid-URL.
changelog=$(cat "$ROOT/tests/fixtures/issue-11/CHANGELOG.md")

out=$(_parse_changelog_content "$changelog" "3.20.1")
check_no_substr "changelog parse: no half markdown link [..]("    "[avo-dynamic_filters #91](" "$out"
check_no_substr "changelog parse: no truncated /pull/ tail"       "/pull/;" "$out"
check_substr   "changelog parse: still emits 3.20.1 header"       "3.20.1:" "$out"

# Total
printf '\n%d/%d passed\n' "$((ran - failed))" "$ran"
exit "$failed"
