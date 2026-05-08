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

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
