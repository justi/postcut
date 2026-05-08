#!/usr/bin/env bash
# Tests for lib/core/save.sh — markdown formatter, models config reader,
# default path helpers.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core/save.sh"

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

check_no_substr() {
  local desc="$1" needle="$2" haystack="$3"
  ran=$((ran + 1))
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    printf 'FAIL  %-60s\n' "$desc"
    printf '       did NOT expect: %s\n' "$needle"
    failed=$((failed + 1))
  else
    printf 'ok    %-60s\n' "$desc"
  fi
}

check_no_lines_matching() {
  local desc="$1" pattern="$2" haystack="$3"
  ran=$((ran + 1))
  local matches
  matches=$(printf '%s' "$haystack" | grep -cE "$pattern" || true)
  if [ "$matches" = "0" ]; then
    printf 'ok    %-60s\n' "$desc"
  else
    printf 'FAIL  %-60s\n' "$desc"
    printf '       pattern matched %s line(s): %s\n' "$matches" "$pattern"
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

# ---- Markdown formatter ----
deltas='rails: 8.0.2 (last seen) → 8.1.3 (current, 2026-03-24)
  [activerecord] 8.1.3: Fix insert_all log message; Restore previous instrumenter
  [actionpack] 8.0.2.1: GHSA-76r7-hhxj-r776 [medium] CVE-2025-55193: ANSI escape injection

puma: 6.6.1 (last seen) → 8.0.1 (current, 2026-04-26)
  7.0.0: Breaking changes; Set default max_keep_alive to 999
'

doc=$(format_markdown_doc "my-app" "claude-opus-4-7" "2026-01-31" "models.dev/claude-opus-4-7" "32 direct deps" "$deltas")

check_substr "doc has H1 with project name"            "# postcut — my-app"             "$doc"
check_substr "doc has metadata table — Model"          "| Model |"                       "$doc"
check_substr "doc has metadata table — Cutoff"         "| Cutoff |"                      "$doc"
check_substr "doc reports update count"                "2 gem(s) post-cutoff"            "$doc"
check_substr "doc has H3 for rails"                    "### rails"                       "$doc"
check_substr "doc has H3 for puma"                     "### puma"                        "$doc"
check_substr "doc keeps version-transition line bold"  "**8.0.2 (last seen)"              "$doc"
check_substr "doc reflows bullets to markdown lists"   "- [activerecord] 8.1.3:"          "$doc"
check_substr "doc preserves CVE/GHSA in bullets"       "GHSA-76r7-hhxj-r776"              "$doc"
check_substr "doc preserves Breaking keyword"          "Breaking changes"                 "$doc"
check_no_lines_matching "doc strips raw two-space indent" '^  \[' "$doc"

# ---- Empty-deltas case ----
empty_doc=$(format_markdown_doc "tiny-app" "claude-opus-4-7" "2026-01-31" "models.dev/claude-opus-4-7" "3 direct deps" "")
check_substr "empty deltas: reports zero updates"  "0 gem(s) post-cutoff"                            "$empty_doc"
check_substr "empty deltas: reassures user"        "training data is current for these dependencies" "$empty_doc"
check_no_substr "empty deltas: no '## Dependency deltas'"  "## Dependency deltas"                    "$empty_doc"

# ---- Models config reader ----
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# No config file → empty stdout
out=$(load_models_config "$tmpdir")
check_eq "no config file → empty output" "" "$out"

# Config with comments and blank lines
mkdir -p "$tmpdir/.config"
cat > "$tmpdir/.config/models" <<EOF
# My models
claude-opus-4-7
   gpt-5
# blank below

claude-haiku-4-5
EOF
out=$(load_models_config "$tmpdir")
expected=$'claude-opus-4-7\ngpt-5\nclaude-haiku-4-5'
check_eq "config: parses 3 models, strips comments+blanks" "$expected" "$out"

# Config that's only comments → empty
cat > "$tmpdir/.config/models" <<EOF
# only comment
# another comment
EOF
out=$(load_models_config "$tmpdir")
check_eq "config: only comments → empty" "" "$out"

# ---- Path helpers ----
check_eq "default_save_dir: appends .postcut"         "/foo/bar/.postcut"  "$(default_save_dir /foo/bar)"
check_eq "default_save_dir: strips trailing slash"    "/foo/bar/.postcut"  "$(default_save_dir /foo/bar/)"
check_eq "default_save_filename: model -> model.md"   "claude-opus-4-7.md" "$(default_save_filename claude-opus-4-7)"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
