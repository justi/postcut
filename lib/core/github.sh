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

  parse_changelog_content "$content" "$versions_csv"
}

# Shared CHANGELOG body parser — used by fetch_changelog_md (HTTP) and by
# adapters that read a CHANGELOG file locally (e.g. ruby_local_notes).
# Args:
#   $1 = full markdown content
#   $2 = comma-separated versions to look up
# Stdout: "  <ver>: <bullet1>; <bullet2>; <bullet3>" per matched version.
#
# Header forms accepted (handled in awk):
#   ## 1.2.3
#   ## v1.2.3
#   ## [1.2.3]
#   ## [1.2.3] - 2024-01-15
#   ## 1.2.3 (2024-01-15)
#   ## Rails 8.1.3 (March 24, 2026) ##
#   ### v1.2.3
#   # 1.2.3
# Sub-headers like "### Active Record" inside a version section don't reset
# the current section — only headers that contain a version number do.
parse_changelog_content() {
  local content="$1"
  local versions_csv="$2"
  [ -z "$content" ] && return 0
  [ -z "$versions_csv" ] && return 0

  printf '%s\n' "$content" | awk -v versions_csv="$versions_csv" '
    BEGIN {
      n = split(versions_csv, vs, ",")
      for (i = 1; i <= n; i++) {
        target[vs[i]] = 1
        buf[vs[i]] = ""
        count[vs[i]] = 0
      }
      current = ""
    }

    # Header line — try to extract a version. If it looks like a header but
    # no version is found, leave `current` alone (sub-header inside a section).
    /^#+[[:space:]]+/ {
      rest = $0
      sub(/^#+[[:space:]]+/, "", rest)
      # Strip optional leading words (e.g. "Rails ", "Sprockets ", etc.)
      while (match(rest, /^[A-Za-z][A-Za-z_-]*[[:space:]]+/)) {
        rest = substr(rest, RSTART + RLENGTH)
      }
      sub(/^v/, "", rest)
      sub(/^\[/, "", rest)
      if (match(rest, /^[0-9]+(\.[0-9]+)+[a-zA-Z0-9.]*/)) {
        current = substr(rest, RSTART, RLENGTH)
      }
      next
    }

    current != "" && (current in target) && /^[[:space:]]*[*\-+][[:space:]]+/ {
      if (count[current] >= 3) next
      bullet = $0
      # Strip ONLY the leading bullet marker. Do not collapse internal
      # whitespace, do not trim trailing — match the old bash parser
      # behavior so output stays byte-identical to pre-refactor runs.
      sub(/^[[:space:]]*[*\-+][[:space:]]+/, "", bullet)
      # Skip trivial "No changes." entries — common in Rails monorepo
      # sub-gems. Without this, ruby_local_notes (when it ships) would
      # see the section as "got something" and prevent fall-through to
      # the richer HTTP source. Trimmed comparison only on this one
      # check; bullet itself is kept unmodified.
      lc = tolower(bullet)
      sub(/^[[:space:]]+/, "", lc)
      sub(/[[:space:]]+$/, "", lc)
      if (lc == "no changes." || lc == "no changes" || lc == "nothing." || lc == "nothing") next
      if (length(bullet) > 140) bullet = substr(bullet, 1, 140)
      if (buf[current] == "") buf[current] = bullet
      else buf[current] = buf[current] "; " bullet
      count[current]++
    }

    END {
      n = split(versions_csv, ordered, ",")
      for (i = 1; i <= n; i++) {
        v = ordered[i]
        if (count[v] > 0) print "  " v ": " buf[v]
      }
    }
  '
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
