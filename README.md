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
  8.1.2.1: CVE-2026-33167 ... CVE-2026-33658 [security]
  8.1.3: Fix JSONGemCoderEncoder; Fix inflections; Silence Dalli warning

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
```

## Modes — local vs HTTP-only

postcut auto-detects whatever toolchain is in `PATH` and uses it for
the bits it can do offline. There's no flag — it just picks up speed
when the tools are around.

**HTTP-only (default, zero deps):**

```bash
# Nothing extra installed beyond bash/curl/jq.
postcut --model claude-opus-4-7 --path ./my-rails-app
```

Every per-gem fact (versions, release notes, advisories) goes over
the network. ~30–90s on a typical Rails app. Set `GITHUB_TOKEN` to
lift the GitHub rate limit.

**Local mode (faster, when Ruby toolchain is present):**

```bash
gem install bundler-audit
bundle-audit update                    # one-time, syncs the DB
export GITHUB_TOKEN=$(gh auth token)   # still needed for version lists
postcut --model claude-opus-4-7 --path ./my-rails-app
```

What goes local automatically when detected:

- **CVE/security** → `bundler-audit check --no-update --format=json`
  (reads `~/.local/share/ruby-advisory-db` synced offline).
  Falls through to GitHub Advisories API if the local DB has nothing
  fresh for a given gem.
- **Gem metadata** (source URI for the gem's repo) → `gem specification <pkg>`
  instead of a `rubygems.org` round-trip.

What still goes over HTTP, always:

- The full version list with publication dates (registry-only data —
  your local install only has one version of any gem).
- Release notes / CHANGELOG content (sub-gem CHANGELOGs in monorepos
  like Rails don't include cross-cutting fixes from sibling sub-gems,
  so we keep `/releases` + raw CHANGELOG fetch as the canonical
  source).

## Status

`v0.2-dev`. Ruby only. No cache yet (~30–90s on a typical Rails app).

## License

MIT
