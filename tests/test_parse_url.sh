#!/usr/bin/env bash
# Tests for parse_github_repo_from_url. Covers tree URLs, raw repo URLs,
# `.git` suffix, deep paths (PRs/files), git@ shorthand, and the
# non-github case which must yield empty output.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core/github.sh"

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

check_eq "tree URL → owner/repo"           "rails/rails"        "$(parse_github_repo_from_url 'https://github.com/rails/rails/tree/v8.1.3')"
check_eq "bare repo URL → owner/repo"      "rails/rails"        "$(parse_github_repo_from_url 'https://github.com/rails/rails')"
check_eq ".git suffix stripped"            "rails/rails"        "$(parse_github_repo_from_url 'https://github.com/rails/rails.git')"
check_eq "non-rails repo"                  "ankane/blazer"      "$(parse_github_repo_from_url 'https://github.com/ankane/blazer')"
check_eq "deep path (PR URL)"              "lostisland/faraday" "$(parse_github_repo_from_url 'https://github.com/lostisland/faraday/pull/1642')"
check_eq "git@ ssh shorthand"              "user/repo"          "$(parse_github_repo_from_url 'git@github.com:user/repo.git')"
check_eq "non-github URL → empty"          ""                   "$(parse_github_repo_from_url 'https://example.com/not/github')"
check_eq "empty input → empty"             ""                   "$(parse_github_repo_from_url '')"

echo
if [ "$failed" -eq 0 ]; then
  printf '%s/%s passed\n' "$ran" "$ran"
  exit 0
else
  printf '%s/%s failed\n' "$failed" "$ran"
  exit 1
fi
