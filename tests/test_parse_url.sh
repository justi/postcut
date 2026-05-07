#!/usr/bin/env bash
# ad-hoc test for parse_github_repo_from_url
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core/github.sh"

cases=(
  "https://github.com/rails/rails/tree/v8.1.3"
  "https://github.com/rails/rails"
  "https://github.com/rails/rails.git"
  "https://github.com/ankane/blazer"
  "https://github.com/lostisland/faraday/pull/1642"
  "git@github.com:user/repo.git"
  "https://example.com/not/github"
)

for c in "${cases[@]}"; do
  out=$(parse_github_repo_from_url "$c")
  printf '%-55s -> %s\n' "$c" "${out:-<empty>}"
done
