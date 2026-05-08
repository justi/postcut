#!/usr/bin/env bash
# Local-first dispatcher.
# dispatch <kind> <adapter> <args...>
#   kind = metadata | notes | advisories
# Prefers <adapter>_local_<kind> when the toolchain is detected and the
# function is sourced; falls back to <adapter>_http_<kind>. Either may
# silently return empty — caller must accept that.

dispatch() {
  local kind="$1"; shift
  local adapter="$1"; shift

  local local_fn="${adapter}_local_${kind}"
  local http_fn="${adapter}_http_${kind}"

  # Try local path first if toolchain present + function available.
  if declare -f "$local_fn" >/dev/null 2>&1 \
     && _postcut_toolchain_available "$adapter"; then
    local out
    out=""
    out=$("$local_fn" "$@") || out=""
    if [ -n "$out" ]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi

  # Fall through to HTTP.
  if declare -f "$http_fn" >/dev/null 2>&1; then
    "$http_fn" "$@"
  fi
}

_postcut_toolchain_available() {
  case "$1" in
    ruby)   command -v gem >/dev/null 2>&1 ;;
    node)   command -v npm >/dev/null 2>&1 ;;
    python) command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1 ;;
    rust)   command -v cargo >/dev/null 2>&1 ;;
    go)     command -v go >/dev/null 2>&1 ;;
    php)    command -v composer >/dev/null 2>&1 ;;
    *)      return 1 ;;
  esac
}
