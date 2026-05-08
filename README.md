# postcut

> CLI that returns a string of dependency deltas since your LLM's training cutoff. Pipe it to any model.

## Install

```bash
git clone https://github.com/justi/postcut.git ~/.postcut
ln -s ~/.postcut/bin/postcut /usr/local/bin/postcut
export GITHUB_TOKEN=$(gh auth token)   # 60/h → 5000/h
```

Requires `bash 3.2+`, `curl`, `jq`. Ruby (`Gemfile.lock`) only for now.

## Usage

```bash
postcut --model claude-opus-4-7 --path ./my-rails-app
```

Output (truncated):

```
RECENT_DEPS_CHANGES (cutoff: 2026-01-31, scope: 5 direct deps (Gemfile)):

rails: 8.1.2 (last seen) → 8.1.3 (current, 2026-03-24)
  [activerecord] 8.1.3: Fix `insert_all` log message; Restore previous instrumenter
  [actionview]   8.1.3: Fix encoding errors for non-ASCII string locals
  [activestorage] 8.1.3: Fix Blob content-type predicates to handle nil
  ...
  8.0.2.1: GHSA-76r7-hhxj-r776 [medium] CVE-2025-55193: ANSI escape injection

rake: 13.3.1 → 13.4.2 (2026-04-16)
  13.4.0: refactor regexp; Fix RDoc formatting
  13.4.2: Preserve ENV[TESTOPTS] when verbose

sqlite3: 2.9.0 → 2.9.4 (2026-05-06)
  2.9.1–2.9.4: vendored SQLite v3.51.1 → v3.53.1
```

```bash
postcut | pbcopy                 # paste into chat
postcut --all                    # include transitive deps
postcut --since 2025-06-01       # override cutoff
postcut --summary                # security/breaking/deprecation only — compact LLM context
```

## Modes — local vs HTTP

postcut auto-detects the Ruby toolchain in `PATH` — no flag. Three
of four data layers go local when `gem` is around; only the version
registry still hits the network.

| Layer | Local source | HTTP fallback |
|---|---|---|
| Versions + dates | — (registry-only) | `rubygems.org/api/v1/versions` |
| Source URI | `gem specification <pkg>` | `rubygems.org/api/v1/gems` |
| Release notes | gem CHANGELOG.md from `gem env gemdir` — Rails meta-gem expands into the 12 sub-gem CHANGELOGs | GitHub Releases → raw CHANGELOG.md |
| CVE / security | `bundler-audit` + ruby-advisory-db | GitHub Advisories DB |

What you gain with the local path:

- **Rails meta-gem expands** into per-component notes (`[activerecord]`,
  `[actionview]`, …) — previously a silent skip, since `rails/rails`
  doesn't ship a top-level CHANGELOG.
- **Zero HTTP** for notes/metadata when the requested version ≤ what's
  installed locally.
- **Offline** beyond one `versions/<gem>.json` call per gem.

To engage everything:

```bash
gem install bundler-audit
bundle-audit update    # one-time, syncs the local CVE DB
```

Set `GITHUB_TOKEN` to lift the rate limit on registry/advisory calls.

## Status

`v0.3-dev` (dual-mode complete for Ruby — metadata, notes, advisories).
No cache yet; ~10–30s on a typical Rails app once warm.

## License

MIT
