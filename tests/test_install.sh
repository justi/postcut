#!/usr/bin/env bash
# Tests for install.sh — fresh install path, idempotency, refusal to
# clobber non-symlink files in the bin dir, config seeding, smoke test.
#
# Sandbox: redirect both INSTALL_DIR and BIN_DIR into the project tree,
# point the installer at a *local* git remote (the project itself) so
# we don't need network access.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/install.sh"

WORKDIR="$ROOT/tests/_install_work"
INSTALL_DIR="$WORKDIR/postcut"
BIN_DIR="$WORKDIR/bin"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
cleanup
mkdir -p "$BIN_DIR"

failed=0
ran=0

check_file() {
  local desc="$1" path="$2"
  ran=$((ran + 1))
  if [ -f "$path" ]; then
    printf 'ok    %-60s\n' "$desc"
  else
    printf 'FAIL  %-60s\n' "$desc"
    printf '       file not found: %s\n' "$path"
    failed=$((failed + 1))
  fi
}

check_link() {
  local desc="$1" path="$2" expected_target="$3"
  ran=$((ran + 1))
  if [ -L "$path" ] && [ "$(readlink "$path")" = "$expected_target" ]; then
    printf 'ok    %-60s\n' "$desc"
  else
    printf 'FAIL  %-60s\n' "$desc"
    printf '       expected link %s → %s\n' "$path" "$expected_target"
    printf '       got: %s\n' "$([ -L "$path" ] && readlink "$path" || echo "(not a symlink)")"
    failed=$((failed + 1))
  fi
}

check_substr() {
  local desc="$1" needle="$2" haystack="$3"
  ran=$((ran + 1))
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    printf 'ok    %-60s\n' "$desc"
  else
    printf 'FAIL  %-60s\n' "$desc"
    printf '       expected substring: %s\n' "$needle"
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

# Use the project's own git history as the "remote" so the test runs
# offline. Pin to the current commit SHA — survives detached-HEAD CI
# checkouts where `rev-parse --abbrev-ref HEAD` would just yield "HEAD"
# and `git checkout HEAD` would do nothing useful.
current_sha=$(git -C "$ROOT" rev-parse HEAD)

run_installer() {
  POSTCUT_INSTALL_DIR="$INSTALL_DIR" \
  POSTCUT_BIN_DIR="$BIN_DIR" \
  POSTCUT_REPO_URL="$ROOT" \
  POSTCUT_GIT_REF="$current_sha" \
  PATH="$BIN_DIR:$PATH" \
  bash "$INSTALLER" 2>&1
}

# ---- 1. Fresh install --------------------------------------------------------
out=$(run_installer)

check_substr "fresh install: clones into INSTALL_DIR"  "cloning"   "$out"
check_substr "fresh install: links into BIN_DIR"       "linking"   "$out"
check_substr "fresh install: seeds config template"    "seeding"   "$out"
check_substr "fresh install: smoke-tests --version"    "installed: postcut" "$out"

check_link "fresh install: symlink target matches" \
  "$BIN_DIR/postcut"  "$INSTALL_DIR/bin/postcut"
check_file "fresh install: clone has bin/postcut"  "$INSTALL_DIR/bin/postcut"
check_file "fresh install: clone has lib/core/save.sh"  "$INSTALL_DIR/lib/core/save.sh"
check_file "fresh install: config seeded"         "$INSTALL_DIR/.config/models"

# Template should be entirely commented out so a re-run doesn't generate
# unintentional snapshots before the user edits it.
ran=$((ran + 1))
uncommented=$(grep -v '^[[:space:]]*#\|^[[:space:]]*$' "$INSTALL_DIR/.config/models" | wc -l | tr -d ' ')
if [ "$uncommented" = "0" ]; then
  printf 'ok    %-60s\n' "config template: all model lines start commented"
else
  printf 'FAIL  %-60s\n' "config template: all model lines start commented"
  printf '       found %s uncommented line(s)\n' "$uncommented"
  failed=$((failed + 1))
fi

# ---- 2. Idempotent re-run ----------------------------------------------------
# User-edited the config — re-running must NOT clobber it.
echo "claude-opus-4-7" >> "$INSTALL_DIR/.config/models"
out=$(run_installer)
check_substr "re-run: pulls existing install"  "updating existing install"  "$out"
check_substr "re-run: keeps user config"       "keeping existing"            "$out"
check_substr "re-run: symlink already in place" "symlink already in place"   "$out"
ran=$((ran + 1))
if grep -qFx "claude-opus-4-7" "$INSTALL_DIR/.config/models"; then
  printf 'ok    %-60s\n' "re-run: user-added model preserved"
else
  printf 'FAIL  %-60s\n' "re-run: user-added model preserved"
  failed=$((failed + 1))
fi

# ---- 3. Refuse to clobber a non-symlink file in bin dir ----------------------
rm -rf "$INSTALL_DIR" "$BIN_DIR/postcut"
mkdir -p "$BIN_DIR"
echo "i was here first" > "$BIN_DIR/postcut"

out=$(run_installer 2>&1) && rc=0 || rc=$?
check_eq    "clobber refusal: exits non-zero"  "1"  "$rc"
check_substr "clobber refusal: explains why"   "exists and is not a symlink"  "$out"
ran=$((ran + 1))
if [ "$(cat "$BIN_DIR/postcut")" = "i was here first" ]; then
  printf 'ok    %-60s\n' "clobber refusal: original file untouched"
else
  printf 'FAIL  %-60s\n' "clobber refusal: original file untouched"
  failed=$((failed + 1))
fi

# ---- 4. POSTCUT_BIN_DIR validation: missing dir is rejected up front --------
rm -rf "$INSTALL_DIR"
out=$(POSTCUT_INSTALL_DIR="$INSTALL_DIR" \
      POSTCUT_BIN_DIR="$WORKDIR/does-not-exist" \
      POSTCUT_REPO_URL="$ROOT" \
      POSTCUT_GIT_REF="$current_sha" \
      bash "$INSTALLER" 2>&1) && rc=0 || rc=$?
check_eq    "missing BIN_DIR override: exits non-zero"  "1"                              "$rc"
check_substr "missing BIN_DIR override: error names it" "is not a directory"             "$out"

# ---- 5. POSTCUT_BIN_DIR validation: read-only dir is rejected ---------------
RO_BIN="$WORKDIR/ro-bin"
rm -rf "$RO_BIN" "$INSTALL_DIR"
mkdir -p "$RO_BIN"
chmod -w "$RO_BIN"
out=$(POSTCUT_INSTALL_DIR="$INSTALL_DIR" \
      POSTCUT_BIN_DIR="$RO_BIN" \
      POSTCUT_REPO_URL="$ROOT" \
      POSTCUT_GIT_REF="$current_sha" \
      bash "$INSTALLER" 2>&1) && rc=0 || rc=$?
check_eq    "read-only BIN_DIR override: exits non-zero"  "1"                            "$rc"
check_substr "read-only BIN_DIR override: error explains" "is not writable"              "$out"
chmod +w "$RO_BIN"

# ---- 6. Smoke-run the installed binary --------------------------------------
rm -rf "$INSTALL_DIR" "$BIN_DIR/postcut"
mkdir -p "$BIN_DIR"
run_installer >/dev/null

version_out=$("$BIN_DIR/postcut" --version 2>&1) && rc=0 || rc=$?
check_eq    "installed binary: --version exits 0"  "0"  "$rc"
check_substr "installed binary: --version output"  "postcut "  "$version_out"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
