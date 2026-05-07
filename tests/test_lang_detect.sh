#!/usr/bin/env bash
# Verifies that postcut emits a language-aware error when no Gemfile.lock
# is found, and that exit code is 1 in every unsupported case.
# Uses --since to skip the models.dev cutoff fetch (offline-friendly).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTCUT="$ROOT/bin/postcut"
FIXTURES="$ROOT/tests/fixtures/lang-detect"

failed=0
ran=0

assert_unsupported() {
  local fixture="$1"
  local needle="$2"
  local desc="$3"

  ran=$((ran + 1))
  local output
  output=$("$POSTCUT" --since 2025-01-01 --path "$FIXTURES/$fixture" 2>&1)
  local code=$?

  if [ "$code" -ne 1 ]; then
    printf 'FAIL  %-30s — expected exit 1, got %s\n' "$desc" "$code"
    printf '       output: %s\n' "$output"
    failed=$((failed + 1))
    return
  fi

  if ! printf '%s' "$output" | grep -qF "$needle"; then
    printf 'FAIL  %-30s — expected %q in stderr\n' "$desc" "$needle"
    printf '       output: %s\n' "$output"
    failed=$((failed + 1))
    return
  fi

  printf 'ok    %-30s\n' "$desc"
}

assert_unsupported "empty-dir" "v0.2 supports only Ruby projects"  "no lockfile, no detection"
assert_unsupported "node"      "Node.js / npm project detected"     "node — package.json"
assert_unsupported "python"    "Python project detected"            "python — pyproject.toml"
assert_unsupported "rust"      "Rust / cargo project detected"      "rust — Cargo.toml"
assert_unsupported "go"        "Go project detected"                "go — go.mod"
assert_unsupported "php"       "PHP / composer project detected"    "php — composer.json"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
