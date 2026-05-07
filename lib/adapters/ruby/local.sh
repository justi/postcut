#!/usr/bin/env bash
# Ruby local-toolchain adapter functions. All emit empty on any failure.
# Caller (router.sh) decides whether to fall back to HTTP equivalents.
#
# Requires: command -v gem  (already gated by router via _postcut_toolchain_available)
# Requires for advisories: command -v bundler-audit  (gracefully skipped if missing)

# ruby_local_metadata <pkg>
# Stdout: best-effort source URI for the gem's GitHub repo, or empty.
# Reads from the locally-installed gem's gemspec metadata block.
ruby_local_metadata() {
  local pkg="$1"
  [ -z "$pkg" ] && return 0

  local meta
  meta=""
  meta=$(gem specification "$pkg" metadata 2>/dev/null) || meta=""
  local uri=""
  if [ -n "$meta" ]; then
    uri=$(printf '%s' "$meta" \
      | awk '/^source_code_uri:/ { sub(/^source_code_uri:[[:space:]]*/, ""); print; exit }')
  fi

  if [ -z "$uri" ]; then
    local hp
    hp=""
    hp=$(gem specification "$pkg" homepage 2>/dev/null) || hp=""
    if [ -n "$hp" ]; then
      uri=$(printf '%s' "$hp" | awk '/^---/ { sub(/^---[[:space:]]*/, ""); print; exit }')
    fi
  fi

  [ -z "$uri" ] && return 0
  printf '%s\n' "$uri"
}

# NOTE: ruby_local_notes intentionally NOT defined.
#
# We tried reading the locally-installed gem's CHANGELOG.md via
# `gem contents <pkg> | grep -i CHANGELOG`, but for Rails monorepo sub-gems
# (actionpack, activesupport, ...) each sub-gem's CHANGELOG covers ONLY its
# own changes. Cross-cutting fixes and CVE listings live in the sibling
# sub-gem's CHANGELOG, or only in the GitHub release body. Pulling the
# local file produces partial / "No changes." output that the router
# then prefers over the much richer HTTP source. Net result: regression
# for Rails projects, the most common case.
#
# Until we have per-monorepo logic (read sibling CHANGELOG paths via
# `gem contents <other_subgem>`) the HTTP path stays canonical for notes.
# `ruby_http_notes` (in fetch.sh) handles /releases + raw CHANGELOG.md
# fallback well enough.

# ruby_local_advisories <pkg> <versions_csv>
# Uses bundler-audit (which reads ruby-advisory-db locally). Output format
# mirrors fetch_github_advisories: "  X.Y.Z: GHSA-XXX [severity] CVE-XXX: summary".
# Note: bundler-audit operates on the cwd Gemfile.lock — it reports CVEs
# against the INSTALLED version, not against post-cutoff versions specifically.
# We filter by package name; per-version mapping uses the advisory's
# patched_versions[] heads where they coincide with our post_versions list.
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
      # semver token in each (the most-specific lower bound). Then exact-
      # match against our post-cutoff versions — avoids the substring
      # false-positive where ">= 7.0.8.1" matched "7.0.8".
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
          # stores the bare hash ("h47h-mwp9-c6q6") and bare CVE id
          # ("2024-47889"), but defend against future format changes.
          ($r.advisory.ghsa // "no-GHSA"
           | if startswith("GHSA-") then . else "GHSA-\(.)" end) as $ghsa
          | ($r.advisory.cve // "no-CVE"
             | if (. == "no-CVE" or startswith("CVE-")) then . else "CVE-\(.)" end) as $cve
          | "  \($hit): \($ghsa) [\($r.advisory.criticality // "unknown")] \($cve): " +
            ($r.advisory.title // "" | gsub("\\s+"; " ") | .[0:140])
        end
    ' 2>/dev/null | sort -u
}
