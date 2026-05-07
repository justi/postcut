#!/usr/bin/env bash
# Parse Gemfile.lock GEM specs section. Stdout: "name version" pairs, one per line.

parse_gemfile_lock() {
  local file="${1:-Gemfile.lock}"
  if [ ! -f "$file" ]; then
    echo "postcut: $file not found" >&2
    return 1
  fi

  awk '
    /^GEM$/                                    { in_gem = 1; next }
    /^[A-Z]/                                   { in_gem = 0; in_specs = 0 }
    in_gem && /^  specs:/                      { in_specs = 1; next }
    in_specs && /^    [a-zA-Z0-9_!.-]+ \([0-9]/ {
      gsub(/[()]/, "")
      print $1 " " $2
    }
  ' "$file" | sort -u
}

# Parse Gemfile (DSL). Stdout: direct gem names, one per line.
# Skips gems sourced from git/github/path (not on rubygems).
parse_gemfile() {
  local file="${1:-Gemfile}"
  [ ! -f "$file" ] && return 0

  awk '
    # Strip inline comments
    { sub(/#.*$/, "") }
    # Match: gem "name" or gem '\''name'\''
    /^[[:space:]]*gem[[:space:]]+["'\''][^"'\'']+["'\'']/ {
      # Skip git/github/path sources (not on rubygems)
      if ($0 ~ /(git:|github:|path:)/) next
      match($0, /["'\''][^"'\'']+["'\'']/)
      name = substr($0, RSTART + 1, RLENGTH - 2)
      print name
    }
  ' "$file" | sort -u
}
