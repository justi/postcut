#!/usr/bin/env bash
# Tests for ruby_check_advisory_db_freshness — silent when DB is recent,
# warns when older than 14 days, no-op when bundler-audit is missing or
# when the override directory isn't a git checkout.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/adapters/ruby/local.sh"

if ! command -v bundler-audit >/dev/null 2>&1; then
  echo "SKIP  bundler-audit not in PATH (function early-returns silently)"
  exit 0
fi

WORKDIR="$ROOT/tests/_advisory_work"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
cleanup
mkdir -p "$WORKDIR"

failed=0
ran=0

check_substr() {
  local desc="$1" needle="$2" haystack="$3"
  ran=$((ran + 1))
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    printf 'ok    %-60s\n' "$desc"
  else
    printf 'FAIL  %-60s\n' "$desc"
    printf '       expected substring: %s\n' "$needle"
    printf '       actual: %s\n' "$haystack"
    failed=$((failed + 1))
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

# Helper: git repo whose only commit is dated `<days>` ago.
make_db_at_age() {
  local target_dir="$1" days_ago="$2"
  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  git -C "$target_dir" init --quiet
  git -C "$target_dir" config user.email "test@example.com"
  git -C "$target_dir" config user.name "test"

  # Compose a commit timestamp `days_ago` days in the past. Bash arith
  # on date(+%s) — works on macOS and Linux without GNU `date -d`.
  local now epoch
  now=$(date +%s)
  epoch=$((now - days_ago * 86400))
  echo "seed" > "$target_dir/seed.txt"
  git -C "$target_dir" add seed.txt
  GIT_AUTHOR_DATE="@$epoch +0000" GIT_COMMITTER_DATE="@$epoch +0000" \
    git -C "$target_dir" commit --quiet -m "seed at age $days_ago days"
}

# 1. Recent DB (1 day old) → silent
make_db_at_age "$WORKDIR/recent" 1
out=$(POSTCUT_ADVISORY_DB_DIR="$WORKDIR/recent" ruby_check_advisory_db_freshness 2>&1)
check_empty "recent DB (1 day): no warning" "$out"

# 2. DB exactly 14 days old → still silent (boundary is "> 14")
make_db_at_age "$WORKDIR/edge" 14
out=$(POSTCUT_ADVISORY_DB_DIR="$WORKDIR/edge" ruby_check_advisory_db_freshness 2>&1)
check_empty "edge case (14 days): no warning" "$out"

# 3. Old DB (30 days) → warns with day count and bundle-audit suggestion
make_db_at_age "$WORKDIR/old" 30
out=$(POSTCUT_ADVISORY_DB_DIR="$WORKDIR/old" ruby_check_advisory_db_freshness 2>&1)
check_substr "old DB (30 days): warning emitted"          "30 days old"          "$out"
check_substr "old DB (30 days): suggests bundle-audit"    "bundle-audit update"  "$out"
check_substr "old DB (30 days): names the path"           "$WORKDIR/old"          "$out"

# 4. Non-git directory → silent (function shouldn't crash on it)
mkdir -p "$WORKDIR/not-a-repo"
echo "noise" > "$WORKDIR/not-a-repo/file"
out=$(POSTCUT_ADVISORY_DB_DIR="$WORKDIR/not-a-repo" ruby_check_advisory_db_freshness 2>&1)
check_empty "non-git directory: silent (no warning)" "$out"

# 5. Missing directory → silent
out=$(POSTCUT_ADVISORY_DB_DIR="$WORKDIR/nonexistent" ruby_check_advisory_db_freshness 2>&1)
check_empty "missing directory: silent (no warning)" "$out"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
