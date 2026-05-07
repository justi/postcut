#!/usr/bin/env bash
# Tests for ruby_local_notes against a controlled fixture gemdir.
# Uses POSTCUT_GEMDIR override so coverage is deterministic regardless
# of what's installed on the host (or whether `gem` is in PATH at all).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core/router.sh"
source "$ROOT/lib/core/github.sh"
source "$ROOT/lib/adapters/ruby/local.sh"

export POSTCUT_GEMDIR="$ROOT/tests/fixtures/local-gemdir"

failed=0
ran=0

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

check_empty() {
  local desc="$1"
  local out="$2"
  ran=$((ran + 1))
  if [ -z "$out" ]; then
    printf 'ok    %-60s\n' "$desc"
  else
    printf 'FAIL  %-60s\n' "$desc"
    printf '       expected empty, got: %s\n' "$out"
    failed=$((failed + 1))
  fi
}

check_nonempty() {
  local desc="$1"
  local out="$2"
  ran=$((ran + 1))
  if [ -n "$out" ]; then
    printf 'ok    %-60s\n' "$desc"
  else
    printf 'FAIL  %-60s\n' "$desc"
    printf '       expected non-empty output\n'
    failed=$((failed + 1))
  fi
}

# ---- 1. Direct gem with simple "## 2.0.0" header ----
out=$(ruby_local_notes regular 2.0.0)
check_nonempty "regular gem: emits notes for installed version" "$out"
check_substr  "regular gem: bullet present"                     "First major bump" "$out"
check_substr  "regular gem: version label '  2.0.0:'"           "  2.0.0:" "$out"

# ---- 2. Rails sub-gem with "## Rails X.Y.Z ##" header ----
out=$(ruby_local_notes activerecord 7.2.1)
check_nonempty "activerecord: notes for 7.2.1"                  "$out"
check_substr  "activerecord: 7.2.1 bullet content"              "Restore previous instrumenter" "$out"
check_substr  "activerecord: emits 7.2.1 label"                 "  7.2.1:" "$out"

# ---- 3. Rails meta-gem stitching ----
out=$(ruby_local_notes rails 7.2.1)
check_substr "rails meta: [activerecord] prefix"                "[activerecord] 7.2.1:" "$out"
check_substr "rails meta: [activesupport] prefix"               "[activesupport] 7.2.1:" "$out"
check_substr "rails meta: [actionpack] prefix"                  "[actionpack] 7.2.1:" "$out"
check_substr "rails meta: activerecord bullet content"          "Restore previous instrumenter" "$out"

# ---- 4. Gating: csv max > installed → empty (HTTP fallback) ----
out=$(ruby_local_notes regular 99.0.0)
check_empty "gating: future version → empty" "$out"

# ---- 5. MED#1 regression: false-positive "## Note: 1.2.3 is deprecated" ----
# The "Note:" header must NOT match — bullets under it ("should not show")
# must be absent, while the real "## 1.2.3" section's bullets must appear.
out=$(ruby_local_notes falsepositive 1.2.3)
check_substr    "falsepositive: real 1.2.3 bullets emitted"     "This is the real 1.2.3 release" "$out"
check_no_substr "falsepositive: 'Note:' header bullets skipped" "should not show as a release note" "$out"

# ---- 6. MED#3 regression: prerelease guard ----
# Installed = prerelease-7.2.0.rc1 (only prerelease available). Querying
# for final 7.2.0 must return empty so the dispatcher falls through to
# HTTP rather than returning the RC's CHANGELOG.
out=$(ruby_local_notes prerelease 7.2.0)
check_empty "prerelease: final-version query → empty (HTTP fallback)" "$out"
out=$(ruby_local_notes prerelease 7.2.0.rc1)
check_empty "prerelease: even RC query → empty (guard rejects all)"   "$out"

# ---- 7. Defensive cases ----
out=$(ruby_local_notes "" "1.0.0")
check_empty "empty pkg → empty" "$out"

out=$(ruby_local_notes regular "")
check_empty "empty csv → empty" "$out"

out=$(ruby_local_notes nonexistent-gem-xyz "1.0.0")
check_empty "unknown gem → empty (no install dir)" "$out"

# ---- 8. Sibling-gem glob safety: pkg='rails' must not match 'rails-html-sanitizer' ----
# Fixture doesn't include the sibling gem so this is a passive guard;
# add a fake sibling and re-check that ruby_local_notes still routes to
# the meta-gem stitching path (sub-gems exist) rather than picking up
# the sibling.
mkdir -p "$POSTCUT_GEMDIR/gems/rails-html-sanitizer-1.7.0"
echo "## 1.7.0" > "$POSTCUT_GEMDIR/gems/rails-html-sanitizer-1.7.0/CHANGELOG.md"
echo "*   sanitizer bullet" >> "$POSTCUT_GEMDIR/gems/rails-html-sanitizer-1.7.0/CHANGELOG.md"

out=$(ruby_local_notes rails 7.2.1)
check_no_substr "glob safety: sibling 'rails-html-sanitizer' not picked" "sanitizer bullet" "$out"
check_substr   "glob safety: meta-gem stitching still works"            "[activerecord]"    "$out"

# Cleanup the sibling
rm -rf "$POSTCUT_GEMDIR/gems/rails-html-sanitizer-1.7.0"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
