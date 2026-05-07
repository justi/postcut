#!/usr/bin/env bash
# GitHub Releases API helper.
# Set GITHUB_TOKEN env var to lift rate limit from 60/h to 5000/h.

# Parse "https://github.com/owner/repo[.git][/...]" → "owner/repo". Empty if not github.
parse_github_repo_from_url() {
  local url="${1:-}"
  [ -z "$url" ] && return 0
  if [[ "$url" =~ github\.com[:/]+([^/]+)/([^/?#]+) ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]%.git}"
    printf '%s/%s\n' "$owner" "$repo"
  fi
}

# Fetch release notes for given versions (CSV). One API call per gem, client-side filter.
# Args: <owner/repo> <versions_csv>
# Stdout: formatted lines, indented 2 spaces, one per matched version. Silent on miss.
fetch_github_release_notes() {
  local repo="$1"
  local versions_csv="$2"
  [ -z "$repo" ] && return 0
  [ -z "$versions_csv" ] && return 0

  local raw url
  url="https://api.github.com/repos/${repo}/releases?per_page=100"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    raw=$(curl -fsSL --max-time 10 -H "Authorization: Bearer ${GITHUB_TOKEN}" "$url" 2>/dev/null) || return 0
  else
    raw=$(curl -fsSL --max-time 10 "$url" 2>/dev/null) || return 0
  fi

  # Bail if rate-limited or repo not found (response is an object, not an array)
  if ! printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
    return 0
  fi

  printf '%s' "$raw" | jq -r --arg vs "$versions_csv" '
    . as $releases
    | ($vs | split(","))
    | map(
        . as $v
        | ($releases | map(select(.tag_name | tostring | contains($v))) | first) as $rel
        | if $rel == null then empty
          else
            ($rel.body // "") as $body
            | ([$body | scan("CVE-[0-9]{4}-[0-9]+")] | unique) as $cves
            | ($body
               | split("\n")
               | map(select(test("^\\s*[*\\-] ")))
               | map(sub("^\\s*[*\\-]\\s+"; ""))
               | map(gsub("\\s+"; " "))
               | map(.[0:140])
               | .[0:3]) as $bullets
            | if ($cves | length) > 0 then
                "  \($v): " + ($cves | join(" ")) + " [security]"
              elif ($bullets | length) > 0 then
                "  \($v): " + ($bullets | join("; "))
              else
                empty
              end
          end
      )
    | .[]
  '
}
