#!/usr/bin/env bash
# Ruby local-toolchain adapter functions. Empty output on any failure;
# the router falls back to the HTTP path when local returns empty.
#
# Activation gate: router checks `command -v gem` before invoking these.
# Additional tools (e.g. bundler-audit) are checked per function and
# gracefully skipped if absent.

# ruby_local_advisories <pkg> <versions_csv>
# Stdout: "  X.Y.Z: GHSA-XXX [severity] CVE-XXXX-NNNN: summary"
# Pulls advisories from the local ruby-advisory-db via bundler-audit.
# Empty if bundler-audit is not installed or has no result for this gem
# whose patched-version intersects with our post-cutoff list.
ruby_local_advisories() {
  local pkg="$1"
  local versions_csv="$2"
  [ -z "$pkg" ] && return 0
  [ -z "$versions_csv" ] && return 0
  command -v bundler-audit >/dev/null 2>&1 || return 0

  local raw
  raw=""
  raw=$(bundler-audit check --no-update --format=json 2>/dev/null) || raw=""
  [ -z "$raw" ] && return 0

  printf '%s' "$raw" | jq -r \
    --arg vs "$versions_csv" \
    --arg pkg "$pkg" '
      ($vs | split(",")) as $versions
      | (.results // [])
      | map(select(.gem.name == $pkg))
      | .[]
      | . as $r
      # Extract concrete patched versions from constraint strings like
      # ">= 7.2.1.1", "~> 7.0.8, >= 7.0.8.5", "~> 6.1.7.9". Take the LAST
      # semver token in each (the most-specific lower bound), then exact-
      # match against post-cutoff versions to avoid substring false
      # positives where ">= 7.0.8.1" matched "7.0.8".
      | [
          ($r.advisory.patched_versions // [])[]
          | [scan("[0-9]+(?:\\.[0-9]+)+")]
          | last
        ]
      | map(select(. != null))
      | map(select(. as $pv | $versions | any(. == $pv)))
      | first as $hit
      | if $hit == null then empty
        else
          # GHSA / CVE prefix is conditional — bundler-audit currently
          # stores bare ids ("h47h-mwp9-c6q6" / "2024-47889"), but defend
          # against future format changes that prepend GHSA-/CVE-.
          ($r.advisory.ghsa // "no-GHSA"
           | if startswith("GHSA-") then . else "GHSA-\(.)" end) as $ghsa
          | ($r.advisory.cve // "no-CVE"
             | if (. == "no-CVE" or startswith("CVE-")) then . else "CVE-\(.)" end) as $cve
          | "  \($hit): \($ghsa) [\($r.advisory.criticality // "unknown")] \($cve): " +
            ($r.advisory.title // "" | gsub("\\s+"; " ") | .[0:140])
        end
    ' 2>/dev/null | sort -u
}

# ruby_http_advisories <pkg> <versions_csv>
# Thin wrapper so the router can fall back to GitHub Advisories when the
# local advisory DB has no fresh entries for the package.
ruby_http_advisories() {
  fetch_github_advisories "rubygems" "$@"
}
