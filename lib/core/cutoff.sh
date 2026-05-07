#!/usr/bin/env bash
# Resolve a model's training cutoff via models.dev/api.json.
# Stdout: YYYY-MM-DD on success. Stderr: error. Returns 1 if model not found.

resolve_cutoff() {
  local model_id="$1"
  local api="${POSTCUT_MODELS_API:-https://models.dev/api.json}"

  local raw
  raw=$(curl -fsSL --max-time 10 "$api") || {
    echo "postcut: failed to fetch $api" >&2
    return 1
  }

  local cutoff
  cutoff=$(printf '%s' "$raw" | jq -r --arg id "$model_id" '
    [.[] | (.models // {}) | to_entries[]
     | select(.key == $id or (.value.id // "") == $id)]
    | first | (.value.knowledge // empty)
  ')

  if [ -z "$cutoff" ] || [ "$cutoff" = "null" ]; then
    echo "postcut: model '$model_id' not found in models.dev (or has no knowledge cutoff)" >&2
    return 1
  fi

  # Normalize YYYY-MM → YYYY-MM-01 (conservative: treat whole month as post-cutoff territory).
  if [[ "$cutoff" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
    cutoff="${cutoff}-01"
  fi

  printf '%s\n' "$cutoff"
}
