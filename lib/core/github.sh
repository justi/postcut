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
        | ($releases | map(
            (.tag_name // "" | tostring) as $tag
            | select(
                $tag == $v
                or $tag == ("v" + $v)
                or ($tag | endswith("-" + $v))
                or ($tag | endswith("/" + $v))
                or ($tag | endswith("-v" + $v))
                or ($tag | endswith("/v" + $v))
              )
          ) | first) as $rel
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

# Fallback: fetch raw CHANGELOG.md (or similar) and extract bullets per version.
# Args: <owner/repo> <versions_csv>
# Stdout: same format as fetch_github_release_notes ("  ver: bullet1; bullet2; bullet3")
fetch_changelog_md() {
  local repo="$1"
  local versions_csv="$2"
  [ -z "$repo" ] && return 0
  [ -z "$versions_csv" ] && return 0

  local content="" branch file url
  for branch in master main; do
    for file in CHANGELOG.md CHANGES.md History.md History.markdown NEWS.md; do
      url="https://raw.githubusercontent.com/${repo}/${branch}/${file}"
      content=$(curl -fsSL --max-time 10 "$url" 2>/dev/null) && break 2
      content=""
    done
  done
  [ -z "$content" ] && return 0

  local -a vs buf count
  IFS=',' read -r -a vs <<< "$versions_csv"
  local n="${#vs[@]}"
  local i
  for ((i = 0; i < n; i++)); do
    buf[$i]=""
    count[$i]=0
  done

  local current_idx=-1 line bullet v idx
  while IFS= read -r line; do
    if [[ "$line" =~ ^#+[[:space:]]+v?\[?([0-9]+(\.[0-9]+)+[a-zA-Z0-9.]*) ]]; then
      v="${BASH_REMATCH[1]}"
      current_idx=-1
      for ((idx = 0; idx < n; idx++)); do
        if [ "${vs[$idx]}" = "$v" ]; then
          current_idx=$idx
          break
        fi
      done
      continue
    fi
    [ "$current_idx" -lt 0 ] && continue
    [ "${count[$current_idx]}" -ge 3 ] && continue
    if [[ "$line" =~ ^[[:space:]]*[-*+][[:space:]]+(.*) ]]; then
      bullet="${BASH_REMATCH[1]}"
      bullet="${bullet:0:140}"
      if [ -n "${buf[$current_idx]}" ]; then
        buf[$current_idx]+="; $bullet"
      else
        buf[$current_idx]="$bullet"
      fi
      count[$current_idx]=$(( count[current_idx] + 1 ))
    fi
  done <<< "$content"

  for ((idx = 0; idx < n; idx++)); do
    if [ -n "${buf[$idx]}" ]; then
      printf '  %s: %s\n' "${vs[$idx]}" "${buf[$idx]}"
    fi
  done
}

# Query GitHub Advisories for an ecosystem package and emit one line per
# advisory whose first_patched_version matches one of the post-cutoff versions.
#
# Args: <ecosystem> <package_name> <versions_csv>
# Stdout: "  X.Y.Z: GHSA-XXX [severity] CVE-XXXX-XXXX: summary"
fetch_github_advisories() {
  local ecosystem="$1"
  local pkg="$2"
  local versions_csv="$3"
  [ -z "$pkg" ] && return 0
  [ -z "$versions_csv" ] && return 0

  local raw url
  url="https://api.github.com/advisories?ecosystem=${ecosystem}&affects=${pkg}&per_page=100"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    raw=$(curl -fsSL --max-time 10 -H "Authorization: Bearer ${GITHUB_TOKEN}" "$url" 2>/dev/null) || return 0
  else
    raw=$(curl -fsSL --max-time 10 "$url" 2>/dev/null) || return 0
  fi

  if ! printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
    return 0
  fi

  printf '%s' "$raw" | jq -r \
    --arg vs "$versions_csv" \
    --arg pkg "$pkg" '
      ($vs | split(",")) as $versions
      | .[]
      | . as $adv
      | (.vulnerabilities[]? | select(.package.name == $pkg) | .first_patched_version) as $fp
      | select($fp != null and $fp != "")
      | select($versions | any(. == $fp))
      | "  \($fp): \($adv.ghsa_id) [\($adv.severity)] \($adv.cve_id // "no-CVE"): \(($adv.summary // "") | gsub("\\s+"; " ") | .[0:140])"
    ' | sort -u
}
