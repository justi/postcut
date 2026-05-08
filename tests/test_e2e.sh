#!/usr/bin/env bash
# End-to-end smoke for `postcut`. Drives the real binary against a temp
# project + temp install root so we exercise the full save flow:
# arg parsing → models config lookup → per-model loop → markdown writer.
#
# Uses --since to skip the models.dev cutoff fetch (offline-friendly).
# The lockfile names a gem that does not exist on rubygems so the
# version-list HTTP call returns 404 and fetch_ruby_delta exits silently
# — we end up with a "0 updates" document, which is exactly the shape
# we want to assert against.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTCUT="$ROOT/bin/postcut"

# Guarded temp dirs inside the project tree (the sandbox blocks /tmp).
WORKDIR="$ROOT/tests/_e2e_work"
INSTALL_ROOT="$ROOT/tests/_e2e_install"

cleanup() { rm -rf "$WORKDIR" "$INSTALL_ROOT"; }
trap cleanup EXIT
cleanup

mkdir -p "$WORKDIR" "$INSTALL_ROOT/.config"

# Minimal lockfile, single gem that won't exist on rubygems.
cat > "$WORKDIR/Gemfile.lock" <<'EOF'
GEM
  remote: https://rubygems.org/
  specs:
    nonexistent-gem-xyz-postcut-e2e (1.0.0)

PLATFORMS
  ruby

DEPENDENCIES
  nonexistent-gem-xyz-postcut-e2e

BUNDLED WITH
   2.5.4
EOF

# Models config with two entries — exercises the per-model loop.
cat > "$INSTALL_ROOT/.config/models" <<'EOF'
# E2E config
test-model-a
test-model-b
EOF

failed=0
ran=0

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

# ---- Single-model run via --model (skips config) ----
out=$("$POSTCUT" --since 2025-09-01 --model single-model --path "$WORKDIR" 2>&1) || true
check_substr "single-model: stderr reports written file"  "wrote $WORKDIR/.postcut/single-model.md" "$out"
check_file   "single-model: .postcut/single-model.md exists" "$WORKDIR/.postcut/single-model.md"

doc=$(cat "$WORKDIR/.postcut/single-model.md")
check_substr "single-model: H1 with project basename"     "# postcut — _e2e_work"      "$doc"
check_substr "single-model: metadata mentions model"      '`single-model`'             "$doc"
check_substr "single-model: cutoff line matches --since"  "2025-09-01 (source: --since)" "$doc"
check_substr "single-model: zero-updates branch reached"  "0 gem(s) post-cutoff"        "$doc"
check_substr "single-model: reassuring empty-deltas note" "training data is current"   "$doc"

# Clean up between runs so the multi-model assertions don't see stale files.
rm -rf "$WORKDIR/.postcut"

# ---- Multi-model run via global config (no --model, no --since) ----
# We still pass --since to skip the models.dev fetch; the config drives
# which model ids the per-model loop iterates over. POSTCUT_CONFIG_DIR
# overrides the install root for config lookup so we don't read the
# user's real ~/.postcut/.config/models.
out=$(POSTCUT_CONFIG_DIR="$INSTALL_ROOT" "$POSTCUT" --since 2025-09-01 --path "$WORKDIR" 2>&1) || true
check_substr "multi-model: writes test-model-a"  "wrote $WORKDIR/.postcut/test-model-a.md"  "$out"
check_substr "multi-model: writes test-model-b"  "wrote $WORKDIR/.postcut/test-model-b.md"  "$out"
check_file   "multi-model: file a exists"  "$WORKDIR/.postcut/test-model-a.md"
check_file   "multi-model: file b exists"  "$WORKDIR/.postcut/test-model-b.md"

doc_a=$(cat "$WORKDIR/.postcut/test-model-a.md")
doc_b=$(cat "$WORKDIR/.postcut/test-model-b.md")
check_substr "multi-model: file a names model"  '`test-model-a`'  "$doc_a"
check_substr "multi-model: file b names model"  '`test-model-b`'  "$doc_b"

# ---- --output rejects multi-model run ----
out=$(POSTCUT_CONFIG_DIR="$INSTALL_ROOT" "$POSTCUT" --since 2025-09-01 --output "$WORKDIR/custom.md" --path "$WORKDIR" 2>&1) && rc=0 || rc=$?
check_eq    "multi-model + --output: exits non-zero"  "2"                                            "$rc"
check_substr "multi-model + --output: explains why"  "--output requires a single model"             "$out"

# ---- Missing-config hint: no config file at all ----
# Point CONFIG_DIR at an empty directory so load_models_config returns
# nothing. Assert durable behavior — the hint mentions the path and the
# default model, the user still gets a doc — rather than exact wording,
# so harmless message tweaks don't break the test.
EMPTY_INSTALL="$ROOT/tests/_e2e_empty_install"
rm -rf "$EMPTY_INSTALL" "$WORKDIR/.postcut"
mkdir -p "$EMPTY_INSTALL"

out=$(POSTCUT_CONFIG_DIR="$EMPTY_INSTALL" "$POSTCUT" --since 2025-09-01 --path "$WORKDIR" 2>&1) || true
check_substr "missing config: hint references the config file path" "$EMPTY_INSTALL/.config/models" "$out"
check_substr "missing config: hint names the default model"         "claude-opus-4-7"               "$out"
check_substr "missing config: hint mentions --model suppression"    "--model"                       "$out"
check_file   "missing config: still produces default doc"           "$WORKDIR/.postcut/claude-opus-4-7.md"

# ---- All-comments-config branch: file exists, every line commented ----
# Distinct from the missing-file case — installer seeds exactly this
# shape, so a fresh-install user must not see "no models config".
COMMENTED_INSTALL="$ROOT/tests/_e2e_commented_install"
rm -rf "$COMMENTED_INSTALL" "$WORKDIR/.postcut"
mkdir -p "$COMMENTED_INSTALL/.config"
cat > "$COMMENTED_INSTALL/.config/models" <<'TPL'
# All commented — same shape as the installer's seeded template
# claude-opus-4-7
# claude-haiku-4-5
TPL

out=$(POSTCUT_CONFIG_DIR="$COMMENTED_INSTALL" "$POSTCUT" --since 2025-09-01 --path "$WORKDIR" 2>&1) || true
check_substr "all-commented: hint distinguishes from missing-file" "no active entries" "$out"
check_substr "all-commented: hint names the file path"              "$COMMENTED_INSTALL/.config/models" "$out"
check_substr "all-commented: still produces default-model doc"      "claude-opus-4-7" "$out"

# Suppression: with --model the hint must NOT appear in either branch.
rm -rf "$WORKDIR/.postcut"
out=$(POSTCUT_CONFIG_DIR="$EMPTY_INSTALL" "$POSTCUT" --model some-model --since 2025-09-01 --path "$WORKDIR" 2>&1) || true
ran=$((ran + 1))
if printf '%s' "$out" | grep -qF -- "no models config" || printf '%s' "$out" | grep -qF -- "no active entries"; then
  printf 'FAIL  %-60s\n' "--model suppresses the missing-config hint"
  printf '       hint leaked: %s\n' "$out"
  failed=$((failed + 1))
else
  printf 'ok    %-60s\n' "--model suppresses the missing-config hint"
fi

# ---- Path-traversal rejection: model id with / or .. is refused ----
# Codex flagged that an id like "vendor/model" or "../escape" used as a
# filename either escapes .postcut/ or fails silently when intermediate
# dirs don't exist. postcut now refuses with exit 2.
mkdir -p "$COMMENTED_INSTALL/.config"
cat > "$COMMENTED_INSTALL/.config/models" <<'TPL'
../escape
TPL
out=$(POSTCUT_CONFIG_DIR="$COMMENTED_INSTALL" "$POSTCUT" --since 2025-09-01 --path "$WORKDIR" 2>&1) && rc=0 || rc=$?
check_eq    "model id with '..' rejected with exit 2"  "2"  "$rc"
check_substr "rejection: error names the offending id"  "../escape"  "$out"

cat > "$COMMENTED_INSTALL/.config/models" <<'TPL'
vendor/model
TPL
out=$(POSTCUT_CONFIG_DIR="$COMMENTED_INSTALL" "$POSTCUT" --since 2025-09-01 --path "$WORKDIR" 2>&1) && rc=0 || rc=$?
check_eq    "model id with '/' rejected with exit 2"   "2"  "$rc"
check_substr "rejection: explains '/' is unsafe"        "must not contain"  "$out"

rm -rf "$EMPTY_INSTALL" "$COMMENTED_INSTALL"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
