#!/usr/bin/env bash
# Tests for `postcut --update` — happy path (fast-forward), dirty-worktree
# refusal, missing-.git refusal, mutex with other flags. Sandboxed against
# a local fake "origin" so the test runs offline.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR="$ROOT/tests/_update_work"
ORIGIN="$WORKDIR/origin"
INSTALL="$WORKDIR/install"

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
    printf '       got: %s\n' "$haystack"
    failed=$((failed + 1))
  fi
}

check_eq() {
  local desc="$1" expected="$2" actual="$3"
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

# Bootstrap a minimal "origin" — just enough of postcut's tree for the
# install-side bin/postcut to source its libs and resolve $ROOT through
# the symlink chain. The update mechanism only cares about the .git
# state, so we don't need every fixture or test.
mkdir -p "$ORIGIN"
cp -R "$ROOT/bin" "$ORIGIN/"
cp -R "$ROOT/lib" "$ORIGIN/"

git -C "$ORIGIN" init --quiet --initial-branch=main
git -C "$ORIGIN" -c user.email=test@example.com -c user.name=postcut-test \
  add bin lib >/dev/null
git -C "$ORIGIN" -c user.email=test@example.com -c user.name=postcut-test \
  commit --quiet -m "initial"

# Clone into the "install" location — this is what `postcut --update`
# will operate on.
git clone --quiet "$ORIGIN" "$INSTALL"
INSTALL_BIN="$INSTALL/bin/postcut"

# Push origin one commit ahead so --update has something to fast-forward.
printf '\n# update test marker\n' >> "$ORIGIN/lib/core/save.sh"
git -C "$ORIGIN" -c user.email=test@example.com -c user.name=postcut-test \
  add lib/core/save.sh >/dev/null
git -C "$ORIGIN" -c user.email=test@example.com -c user.name=postcut-test \
  commit --quiet -m "ahead by one"

before_install=$(git -C "$INSTALL" rev-parse --short HEAD)
ahead_origin=$(git -C "$ORIGIN" rev-parse --short HEAD)

# ---- 1. Happy path -----------------------------------------------------------
out=$("$INSTALL_BIN" --update 2>&1)
after_install=$(git -C "$INSTALL" rev-parse --short HEAD)

check_substr "happy: prints before → after"  "$before_install → $after_install"  "$out"
check_substr "happy: prints commit count"    "1 commit(s)"                       "$out"
check_eq     "happy: install HEAD now matches origin"  "$ahead_origin"  "$after_install"

# ---- 2. Already up to date ---------------------------------------------------
out=$("$INSTALL_BIN" --update 2>&1)
check_substr "no-op: prints 'already up to date'"  "already up to date"  "$out"

# ---- 3. Mutex with other flags -----------------------------------------------
out=$("$INSTALL_BIN" --update --model foo 2>&1 || true)
check_substr "mutex: --update --model rejected"  "takes no other flags"  "$out"

out=$("$INSTALL_BIN" --update --since 2025-01-01 2>&1 || true)
check_substr "mutex: --update --since rejected"  "takes no other flags"  "$out"

# ---- 4. Dirty-worktree refusal -----------------------------------------------
# Use an untracked file rather than editing a sourced lib script — bin/postcut
# would execute the modified shell on next launch and the test would crash.
touch "$INSTALL/dirty-marker"
out=$("$INSTALL_BIN" --update 2>&1 || true)
check_substr "dirty: refuses with helpful message"  "uncommitted changes"  "$out"
rm -f "$INSTALL/dirty-marker"

# ---- 5. Missing .git ---------------------------------------------------------
NOGIT_INSTALL="$WORKDIR/nogit"
cp -R "$INSTALL" "$NOGIT_INSTALL"
rm -rf "$NOGIT_INSTALL/.git"
out=$("$NOGIT_INSTALL/bin/postcut" --update 2>&1 || true)
check_substr "no-git: refuses with re-run-install hint"  "is not a git clone"  "$out"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
