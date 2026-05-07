#!/usr/bin/env bash
# Smoke tests for ruby_local_notes. Requires `gem` in PATH and the rails
# meta-gem installed (with at least one of its sub-gems — usually all
# install together). Skips otherwise.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core/router.sh"
source "$ROOT/lib/core/github.sh"
source "$ROOT/lib/adapters/ruby/local.sh"

if ! command -v gem >/dev/null 2>&1; then
  echo "SKIP  no \`gem\` in PATH (test requires Ruby toolchain)"
  exit 0
fi

GEMDIR=$(gem env gemdir 2>/dev/null) || GEMDIR=""
if [ -z "$GEMDIR" ]; then
  echo "SKIP  gem env gemdir empty"
  exit 0
fi

# Pick the highest installed activerecord version as the test target.
AR_DIR=$(ls -d "${GEMDIR}/gems/activerecord-"[0-9]*/ 2>/dev/null | sort -V | tail -1)
AR_DIR="${AR_DIR%/}"
if [ -z "$AR_DIR" ] || [ ! -f "${AR_DIR}/CHANGELOG.md" ]; then
  echo "SKIP  no activerecord with CHANGELOG.md installed"
  exit 0
fi
AR_VERSION="${AR_DIR##*/activerecord-}"

# Pick the highest installed rails meta-gem version (may differ from AR if
# user has rails partially installed); skip the rails-specific assertions
# if there's no rails meta directory.
RAILS_DIR=$(ls -d "${GEMDIR}/gems/rails-"[0-9]*/ 2>/dev/null | sort -V | tail -1)
RAILS_DIR="${RAILS_DIR%/}"
RAILS_VERSION=""
[ -n "$RAILS_DIR" ] && RAILS_VERSION="${RAILS_DIR##*/rails-}"

failed=0
ran=0

check_nonempty() {
  local desc="$1"
  local out="$2"
  ran=$((ran + 1))
  if [ -n "$out" ]; then
    printf 'ok    %-55s\n' "$desc"
  else
    printf 'FAIL  %-55s\n' "$desc"
    printf '       expected non-empty output\n'
    failed=$((failed + 1))
  fi
}

check_empty() {
  local desc="$1"
  local out="$2"
  ran=$((ran + 1))
  if [ -z "$out" ]; then
    printf 'ok    %-55s\n' "$desc"
  else
    printf 'FAIL  %-55s\n' "$desc"
    printf '       expected empty, got: %s\n' "$out"
    failed=$((failed + 1))
  fi
}

check_substr() {
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

# 1. Direct gem (activerecord) — installed version should produce notes.
out=$(ruby_local_notes activerecord "$AR_VERSION")
check_nonempty "activerecord notes for installed version" "$out"
check_substr  "activerecord output starts with version label" "  ${AR_VERSION}:" "$out"

# 2. Rails meta-gem — must emit lines with [activerecord] sub-gem prefix
#    when the installed sub-gem version matches the requested version.
if [ -n "$RAILS_VERSION" ]; then
  # Use AR_VERSION for the csv since that's what's actually parseable;
  # rails meta loops over sub-gems with the same csv, so [activerecord]
  # lines should appear iff activerecord-AR_VERSION's CHANGELOG mentions it.
  out=$(ruby_local_notes rails "$AR_VERSION")
  check_substr "rails meta emits [activerecord] prefix" "[activerecord]" "$out"
else
  printf 'SKIP  rails meta-gem not installed — skipping meta tests\n'
fi

# 3. Gating: csv contains a version higher than installed → empty output.
#    Pick a version that's certainly higher (bump major).
INSTALLED_MAJOR="${AR_VERSION%%.*}"
FUTURE_MAJOR=$((INSTALLED_MAJOR + 10))
FUTURE_VERSION="${FUTURE_MAJOR}.0.0"
out=$(ruby_local_notes activerecord "$FUTURE_VERSION")
check_empty "gating: csv max > installed → empty (HTTP fallback)" "$out"

# 4. Empty pkg → empty output (defensive).
out=$(ruby_local_notes "" "1.0.0")
check_empty "empty pkg returns empty" "$out"

# 5. Empty csv → empty output (defensive).
out=$(ruby_local_notes activerecord "")
check_empty "empty csv returns empty" "$out"

# 6. Unknown gem → empty (no install dir).
out=$(ruby_local_notes this-gem-definitely-does-not-exist-xyz "1.0.0")
check_empty "unknown gem returns empty" "$out"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
