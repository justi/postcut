#!/usr/bin/env bash
# Markdown formatter + global models config reader.
# Used by `bin/postcut` to turn delta blocks into a self-contained
# offline-ready document, and to drive the multi-model snapshot loop.

# Group gems whose post-cutoff content is byte-identical under a single
# combined header. Triggered by monorepos that publish a unified
# CHANGELOG to all sub-gems (e.g. sentry-rails + sentry-ruby from the
# getsentry/sentry-ruby repo emit identical bullets). Pure cosmetic —
# update_count stays per-gem. See issue #12.
#
# Stdin: raw delta blocks (`name: ... (current, ...)` + indented bullets,
# blank-line separated).
# Stdout: same structure, with shared blocks merged into `name1, name2: ...`.
_dedup_monorepo_deltas() {
  awk '
    BEGIN { block_count = 0 }
    function flush_block() {
      if (cur_name == "") return
      key = cur_rest "\x01" cur_bullets
      if (key in seen) {
        groups[seen[key]] = groups[seen[key]] ", " cur_name
      } else {
        seen[key] = block_count
        order[block_count] = key
        groups[block_count] = cur_name
        block_count++
      }
      cur_name = ""; cur_rest = ""; cur_bullets = ""
    }

    /^[a-zA-Z0-9_.-]+: .* \(current,/ {
      flush_block()
      idx = index($0, ":")
      cur_name = substr($0, 1, idx - 1)
      cur_rest = substr($0, idx + 2)
      next
    }
    /^[[:space:]]/ { cur_bullets = cur_bullets $0 "\n"; next }
    /^[[:space:]]*$/ { next }

    END {
      flush_block()
      for (i = 0; i < block_count; i++) {
        key = order[i]
        sep = index(key, "\x01")
        rest = substr(key, 1, sep - 1)
        bullets = substr(key, sep + 1)
        if (i > 0) print ""
        printf "%s: %s\n", groups[i], rest
        printf "%s", bullets
      }
    }
  '
}

# format_markdown_doc <project> <model> <cutoff> <cutoff_source> <scope_label> <deltas>
# Emits a markdown document on stdout. The body (`<deltas>`) is the raw
# fetch_ruby_delta output — header lines + indented bullets — and we
# reflow it into per-gem H3 sections so it parses cleanly for both an
# LLM and a human reader.
format_markdown_doc() {
  local project="$1"
  local model="$2"
  local cutoff="$3"
  local cutoff_source="$4"
  local scope_label="$5"
  local deltas="$6"

  local generated
  generated=$(date -u '+%Y-%m-%d')

  # Count gem updates by counting non-indented, non-blank lines that look
  # like a delta header ("name: vX (last seen) → vY (...)").
  local update_count=0
  if [ -n "$deltas" ]; then
    update_count=$(printf '%s\n' "$deltas" | grep -cE '^[a-zA-Z0-9_.-]+: .* \(current,' || true)
  fi

  printf '# postcut — %s\n\n' "$project"
  printf '| Field | Value |\n'
  printf '|---|---|\n'
  printf '| Generated | %s |\n' "$generated"
  printf '| Model | `%s` |\n' "$model"
  printf '| Cutoff | %s (source: %s) |\n' "$cutoff" "$cutoff_source"
  printf '| Scope | %s |\n' "$scope_label"
  printf '| Updates | %s gem(s) post-cutoff |\n' "$update_count"
  printf '\n'

  if [ -z "$deltas" ] || [ "$update_count" -eq 0 ]; then
    printf 'No post-cutoff updates in scope. Your training data is current for these dependencies.\n'
    return 0
  fi

  printf '## Dependency deltas\n\n'
  printf '> Each section below describes how a gem changed since the model'\''s training cutoff.\n'
  printf '> Use the post-cutoff version'\''s API; flag breaking-change versions explicitly.\n\n'

  # Reflow: a header line opens a new H3, bullet lines become markdown
  # list items. Blank lines separate gems. Markdown links inside bullets
  # are kept intact since they often point to PRs/CVEs.
  #
  # Header regex now accepts comma-joined gem names so monorepo siblings
  # merged by _dedup_monorepo_deltas (e.g. "sentry-rails, sentry-ruby:")
  # still parse as a section header.
  printf '%s\n' "$deltas" | _dedup_monorepo_deltas | awk '
    /^[a-zA-Z0-9_.-]+(, [a-zA-Z0-9_.-]+)*: .* \(current,/ {
      if (in_block) print ""
      # split "name(, name)*: rest"
      idx = index($0, ":")
      name = substr($0, 1, idx - 1)
      rest = substr($0, idx + 1)
      sub(/^ /, "", rest)
      printf "### %s\n\n", name
      printf "**%s**\n\n", rest
      in_block = 1
      next
    }
    /^[[:space:]]+/ {
      # bullet line — preserve indent semantics by emitting a markdown
      # list item. Drop the leading two spaces postcut emits and replace
      # with `- `. Use `print` with concatenation rather than printf — on
      # some awks, `printf -- "..."` mis-parses the `--` as an option
      # separator and emits a syntax error.
      sub(/^[[:space:]]+/, "")
      print "- " $0
      next
    }
    /^[[:space:]]*$/ { next }  # already handled by header-driven spacing
  '
}

# load_models_config <install_root>
# Reads <install_root>/.config/models — one model id per line, # for
# comments, blanks ignored. Stdout: the model list (one per line) or
# nothing if the file is missing.
load_models_config() {
  local install_root="$1"
  local config_file="${install_root}/.config/models"
  [ -f "$config_file" ] || return 0
  awk '
    { sub(/#.*$/, "") }
    /^[[:space:]]*$/ { next }
    { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print }
  ' "$config_file"
}

# default_save_dir <project_path>
# Where to drop generated docs by default — `.postcut/` inside the
# project, so it's gitignore-friendly per-project.
default_save_dir() {
  printf '%s/.postcut\n' "${1%/}"
}

# default_save_filename <model>
# `<model>.md` — one file per model so the user can `cat .postcut/<model>.md`
# and pipe it directly into a chat session.
default_save_filename() {
  printf '%s.md\n' "$1"
}
