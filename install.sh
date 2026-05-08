#!/usr/bin/env bash
# postcut installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/justi/postcut/main/install.sh | bash
#   bash install.sh                  # if you already cloned the repo
#
# What it does:
#   1. Verifies git/curl/jq are present
#   2. Clones (or pulls) the repo into POSTCUT_INSTALL_DIR (default: ~/.postcut)
#   3. Symlinks bin/postcut into the first writable bin dir on PATH
#   4. Seeds POSTCUT_INSTALL_DIR/.config/models with a commented template
#   5. Probes for `gh` auth and prints (does not write) the GITHUB_TOKEN
#      export line you may want to add to your shell rc
#   6. Smoke-tests `postcut --version`
#
# Env overrides (mostly for tests):
#   POSTCUT_INSTALL_DIR  install root (default: $HOME/.postcut)
#   POSTCUT_BIN_DIR      where to drop the symlink (default: auto-detected)
#   POSTCUT_REPO_URL     git remote (default: https://github.com/justi/postcut.git)
#   POSTCUT_GIT_REF      branch/tag/SHA to check out (default: main)
#
# The whole installer is wrapped in `_postcut_install` and only invoked
# at the very end. If the script body is truncated mid-stream (e.g.
# `curl | bash` over a flaky connection), bash reaches EOF before the
# call site, the function never runs, and no partial side effects land.

set -euo pipefail

_postcut_install() {
  local INSTALL_DIR="${POSTCUT_INSTALL_DIR:-$HOME/.postcut}"
  local REPO_URL="${POSTCUT_REPO_URL:-https://github.com/justi/postcut.git}"
  local GIT_REF="${POSTCUT_GIT_REF:-main}"

  log() { printf '%s\n' "$*" >&2; }
  err() { printf 'install.sh: %s\n' "$*" >&2; }

  # 1. Dependency check ------------------------------------------------------
  local missing=()
  local cmd
  for cmd in git curl jq; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    err "missing required commands: ${missing[*]}"
    err "install them first (e.g. 'brew install ${missing[*]}' on macOS)"
    return 1
  fi

  # 2. Clone or update -------------------------------------------------------
  if [ -d "$INSTALL_DIR/.git" ]; then
    # Refuse to clobber a dirty worktree — the user may have local edits
    # they want to keep. Pull --ff-only would error out anyway, but the
    # raw git message is opaque; this surfaces the situation early.
    local dirty
    dirty=$(git -C "$INSTALL_DIR" status --porcelain 2>/dev/null || true)
    if [ -n "$dirty" ]; then
      err "$INSTALL_DIR has uncommitted changes:"
      printf '%s\n' "$dirty" >&2
      err "commit, stash, or revert them and re-run, or remove the directory"
      return 1
    fi
    log "==> updating existing install at $INSTALL_DIR"
    git -C "$INSTALL_DIR" fetch --quiet origin "$GIT_REF"
    git -C "$INSTALL_DIR" checkout --quiet "$GIT_REF"
    # Only pull if we're on a branch (skip for tags / detached SHAs).
    if git -C "$INSTALL_DIR" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
      git -C "$INSTALL_DIR" pull --ff-only --quiet origin "$GIT_REF"
    fi
  else
    log "==> cloning $REPO_URL into $INSTALL_DIR"
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
    # Check out the requested ref after clone — this works for branches,
    # tags, and full SHAs uniformly (unlike `git clone --branch`, which
    # rejects raw SHAs).
    git -C "$INSTALL_DIR" checkout --quiet "$GIT_REF"
  fi

  # 3. Symlink into a bin dir on PATH ---------------------------------------
  pick_bin_dir() {
    if [ -n "${POSTCUT_BIN_DIR:-}" ]; then
      printf '%s\n' "$POSTCUT_BIN_DIR"
      return
    fi
    local d
    for d in "/usr/local/bin" "$HOME/.local/bin" "$HOME/bin"; do
      [ -d "$d" ] || continue
      case ":$PATH:" in *":$d:"*) ;; *) continue ;; esac
      [ -w "$d" ] || continue
      printf '%s\n' "$d"
      return
    done
  }

  local bin_dir target_link link_path
  bin_dir=$(pick_bin_dir)
  target_link="$INSTALL_DIR/bin/postcut"

  if [ -n "$bin_dir" ]; then
    link_path="$bin_dir/postcut"
    if [ -L "$link_path" ] && [ "$(readlink "$link_path")" = "$target_link" ]; then
      log "==> symlink already in place: $link_path"
    else
      if [ -e "$link_path" ] && [ ! -L "$link_path" ]; then
        err "$link_path exists and is not a symlink — refusing to overwrite"
        err "remove it manually if you want install.sh to manage it"
        return 1
      fi
      log "==> linking $link_path → $target_link"
      ln -sf "$target_link" "$link_path"
    fi
  else
    log "==> no writable bin dir found on PATH"
    log "    add this line to your shell rc to use postcut:"
    log "      export PATH=\"$INSTALL_DIR/bin:\$PATH\""
  fi

  # 4. Seed config template (only if absent) --------------------------------
  local config_dir="$INSTALL_DIR/.config"
  local config_file="$config_dir/models"
  mkdir -p "$config_dir"
  if [ ! -f "$config_file" ]; then
    log "==> seeding $config_file with a commented template"
    cat > "$config_file" <<'TEMPLATE'
# postcut models config — one model id per line, # for comments.
# Listed models are snapshotted on each `postcut` run; pick the ones
# you might switch to during a flight.

# Default — uncomment to include:
# claude-opus-4-7
# claude-haiku-4-5
# gpt-5
TEMPLATE
  else
    log "==> keeping existing $config_file"
  fi

  # 5. GITHUB_TOKEN hint -----------------------------------------------------
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    log ""
    log "==> 'gh' CLI is authenticated. To lift the GitHub rate limit"
    log "    (60/h → 5000/h) add this line to your shell rc:"
    log ""
    log "      export GITHUB_TOKEN=\"\$(gh auth token)\""
  fi

  # 6. Smoke test ------------------------------------------------------------
  if [ -n "$bin_dir" ]; then
    local version_out
    if version_out=$("$bin_dir/postcut" --version 2>&1); then
      log ""
      log "==> installed: $version_out"
      log "    next: cd into a Ruby project, edit $config_file, run 'postcut'"
    else
      err "postcut installed but --version failed: $version_out"
      return 1
    fi
  fi
}

# Truncation guard: only call _postcut_install once the whole script has
# parsed successfully. If `curl | bash` is cut short, bash never reaches
# this line and the function body is never invoked.
_postcut_install "$@"
