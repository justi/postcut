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
#   POSTCUT_GIT_REF      branch/tag to check out (default: main)

set -euo pipefail

INSTALL_DIR="${POSTCUT_INSTALL_DIR:-$HOME/.postcut}"
REPO_URL="${POSTCUT_REPO_URL:-https://github.com/justi/postcut.git}"
GIT_REF="${POSTCUT_GIT_REF:-main}"

log() { printf '%s\n' "$*" >&2; }
err() { printf 'install.sh: %s\n' "$*" >&2; }

# 1. Dependency check ----------------------------------------------------------
missing=()
for cmd in git curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ "${#missing[@]}" -gt 0 ]; then
  err "missing required commands: ${missing[*]}"
  err "install them first (e.g. 'brew install ${missing[*]}' on macOS)"
  exit 1
fi

# 2. Clone or pull -------------------------------------------------------------
if [ -d "$INSTALL_DIR/.git" ]; then
  log "==> updating existing install at $INSTALL_DIR"
  git -C "$INSTALL_DIR" fetch --quiet origin "$GIT_REF"
  git -C "$INSTALL_DIR" checkout --quiet "$GIT_REF"
  git -C "$INSTALL_DIR" pull --ff-only --quiet origin "$GIT_REF"
else
  log "==> cloning $REPO_URL into $INSTALL_DIR"
  git clone --quiet --branch "$GIT_REF" "$REPO_URL" "$INSTALL_DIR"
fi

# 3. Symlink into a bin dir on PATH -------------------------------------------
# Try the user-supplied dir first, then the conventional candidates.
# A directory is "good" if it exists, is on PATH, and is writable.
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
      exit 1
    fi
    log "==> linking $link_path → $target_link"
    ln -sf "$target_link" "$link_path"
  fi
else
  log "==> no writable bin dir found on PATH"
  log "    add this line to your shell rc to use postcut:"
  log "      export PATH=\"$INSTALL_DIR/bin:\$PATH\""
fi

# 4. Seed config template (only if absent) ------------------------------------
config_dir="$INSTALL_DIR/.config"
config_file="$config_dir/models"
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

# 5. GITHUB_TOKEN hint ---------------------------------------------------------
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  log ""
  log "==> 'gh' CLI is authenticated. To lift the GitHub rate limit"
  log "    (60/h → 5000/h) add this line to your shell rc:"
  log ""
  log "      export GITHUB_TOKEN=\"\$(gh auth token)\""
fi

# 6. Smoke test ----------------------------------------------------------------
if [ -n "$bin_dir" ]; then
  if version_out=$("$bin_dir/postcut" --version 2>&1); then
    log ""
    log "==> installed: $version_out"
    log "    next: cd into a Ruby project, edit $config_file, run 'postcut'"
  else
    err "postcut installed but --version failed: $version_out"
    exit 1
  fi
fi
