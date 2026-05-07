#!/usr/bin/env bash
# Parse Gemfile.lock GEM specs section. Stdout: "name version" pairs, one per line.

parse_gemfile_lock() {
  local file="${1:-Gemfile.lock}"
  if [ ! -f "$file" ]; then
    echo "postcut: $file not found" >&2
    return 1
  fi

  # Multi-platform gems (e.g. sqlite3, nokogiri, thruster) appear in
  # Gemfile.lock with one row per platform: "sqlite3 (2.7.3-arm64-darwin)",
  # "sqlite3 (2.7.3-x86_64-linux-gnu)", etc. We dedupe by name, keeping
  # the first occurrence — fetch_ruby_delta computes pre/post-cutoff
  # versions independently from RubyGems, so the lockfile version is
  # only used as an identifier here.
  awk '
    /^GEM$/                                    { in_gem = 1; next }
    /^[A-Z]/                                   { in_gem = 0; in_specs = 0 }
    in_gem && /^  specs:/                      { in_specs = 1; next }
    in_specs && /^    [a-zA-Z0-9_!.-]+ \([0-9]/ {
      gsub(/[()]/, "")
      if (!seen[$1]++) print $1 " " $2
    }
  ' "$file" | sort
}

# Parse Gemfile (DSL). Stdout: direct gem names, one per line.
# Skips gems sourced from git/github/path (not on rubygems).
# If Gemfile has a `gemspec` directive (gem source repos), also parses
# the *.gemspec next to it for add_*_dependency entries.
parse_gemfile() {
  local file="${1:-Gemfile}"
  [ ! -f "$file" ] && return 0

  local from_gemfile from_gemspec=""
  from_gemfile=$(awk '
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
  ' "$file")

  # Check for `gemspec` directive — gem source repos pull deps from
  # the .gemspec file, not from explicit `gem` lines.
  if grep -qE '^[[:space:]]*gemspec\b' "$file"; then
    local dir
    dir=$(dirname "$file")
    local spec
    for spec in "$dir"/*.gemspec; do
      [ -f "$spec" ] || continue
      from_gemspec=$(awk '
        { sub(/#.*$/, "") }
        # spec.add_dependency / .add_runtime_dependency / .add_development_dependency
        /\.add(_runtime|_development)?_dependency[[:space:]]*\(?[[:space:]]*["'\'']/ {
          match($0, /["'\''][^"'\'']+["'\'']/)
          name = substr($0, RSTART + 1, RLENGTH - 2)
          print name
        }
      ' "$spec")
      break
    done
  fi

  printf '%s\n%s\n' "$from_gemfile" "$from_gemspec" | grep -v '^$' | sort -u
}
