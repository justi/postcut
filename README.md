# postcut

> A lightweight, offline-first CLI that returns a string of dependency changes since your LLM's training cutoff — feed it to any model.

## What

`postcut` reads your project's lockfile, queries package registries, filters releases by your model's cutoff date, and emits a compact string of post-cutoff deltas. Pipe it into Claude, Codex, Cursor, or any other LLM-driven tool to ground its answers in what your dependencies actually look like *now*.

## Why

LLMs hallucinate library APIs that no longer exist or miss patches released after their training cutoff. Existing tools (Context7, DevDocs MCP, nanocontext) return *full* docs on demand. `postcut` is the inverse — passive, deltas-only, project-scoped.

## Quick start

```bash
# Auto-detect lockfile, default cutoff (6 months ago)
postcut

# Pass to your LLM
postcut | pbcopy
postcut --top 5 | claude
```

## Status

Pre-v0.1. Bash-based, zero runtime deps beyond `curl` and `jq`.

## License

MIT
