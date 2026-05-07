# postcut

> A lightweight CLI that returns a string of dependency deltas since your LLM's training cutoff — feed it to any model.

## What

`postcut` reads your project's lockfile, looks up your model's training cutoff via [models.dev](https://models.dev), queries the package registry for releases since that date, and emits a compact string. Pipe it into Claude, Codex, Cursor, or any other LLM-driven tool to ground its answers in what your dependencies actually look like *now* — including security advisories the model has never seen.

## Why

LLMs hallucinate library APIs that no longer exist and miss patches released after their training cutoff. Existing tools (Context7, DevDocs MCP, nanocontext) return *full* docs on demand. `postcut` is the inverse — passive, deltas-only, project-scoped, runs in seconds.

## Requirements

- Bash 3.2+ (works with macOS's stock Bash — no `brew install bash` needed)
- `curl`, `jq`
- A lockfile in your project (Ruby's `Gemfile.lock` for now; npm/pypi/cargo coming)

## Install

```bash
git clone https://github.com/justi/postcut.git ~/.postcut
ln -s ~/.postcut/bin/postcut /usr/local/bin/postcut
```

Optional but strongly recommended — set a GitHub token to lift rate limits from 60/h to 5000/h:

```bash
export GITHUB_TOKEN=$(gh auth token)   # if you use the gh CLI
# or paste a token from github.com/settings/tokens (no scopes needed for public repos)
```

## Examples

### Small project — blazer's own development setup

5 direct deps in `Gemfile`. Default cutoff is `claude-opus-4-7` (2026-01-31).

```
$ postcut --path ~/Projects/blazer

RECENT_DEPS_CHANGES (cutoff: 2026-01-31, source: models.dev/claude-opus-4-7, scope: 5 direct deps (Gemfile)):

minitest: 6.0.1 (last seen) → 6.0.6 (current, 2026-05-01)

rails: 8.1.2 (last seen) → 8.1.3 (current, 2026-03-24)
  8.1.2.1: CVE-2026-33167 CVE-2026-33168 CVE-2026-33169 CVE-2026-33170 CVE-2026-33173 CVE-2026-33174 CVE-2026-33176 CVE-2026-33195 CVE-2026-33202 CVE-2026-33658 [security]
  8.1.3: Fix `JSONGemCoderEncoder` to correctly serialize custom object hash keys.; Fix inflections to better handle overlapping acronyms.; Silence Dalli 4.0+ warning when using `ActiveSupport::Cache::MemCacheStore`.

rake: 13.3.1 (last seen) → 13.4.2 (current, 2026-04-16)
  13.4.0: refactor: fix ambiguous regexp / assertion in tests; Fix RDoc formatting; Document implicit file tasks
  13.4.1: Add `lib/rake/options.rb` to gemspec
  13.4.2: Preserve `ENV["TESTOPTS"]` when verbose is enabled

sqlite3: 2.9.0 (last seen) → 2.9.4 (current, 2026-05-06)
  2.9.1: Vendored sqlite is updated to v3.51.2 (from v3.51.1).
  2.9.2: Vendored sqlite is updated to v3.51.3 (from v3.51.2).
  2.9.3: Vendored sqlite is updated to v3.53.0 (from v3.51.3).
  2.9.4: Vendored sqlite is updated to v3.53.1 (from v3.53.0).
```

### Security-sensitive surface — actionpack with CVE

```
$ postcut --path ./my-rails-app

actionpack: 8.1.2 (last seen) → 8.1.3 (current, 2026-03-24)
  8.1.2.1: CVE-2026-33167 ... CVE-2026-33658 [security]
  8.1.3: Fix `JSONGemCoderEncoder` ...; Fix inflections ...
  8.1.2.1: GHSA-pgm4-439c-5jp6 [low] CVE-2026-33167: Rails has a possible XSS vulnerability in its Action Pack debug exceptions
```

Three layers stacked: (1) regex CVE list from `/releases` body, (2) curated bullets from release notes, (3) structured GitHub Advisories Database entry with severity and one-line summary.

### Pipe into your LLM workflow

```bash
postcut | pbcopy                              # paste into any chat
postcut > .postcut-context.txt                # stash for prompt
postcut | claude -p "explain what changed"    # direct pipe
```

### Specify the model

`postcut` looks up the cutoff from [models.dev](https://models.dev/api.json):

```bash
postcut --model claude-sonnet-4-6     # cutoff: 2025-08-31
postcut --model claude-opus-4-7       # cutoff: 2026-01-31  (default)
postcut --model claude-haiku-4-5      # cutoff: 2025-02-28
```

Or override the cutoff entirely:

```bash
postcut --since 2025-06-01
```

### Direct deps only (default) vs all deps

By default `postcut` reads `Gemfile` and filters `Gemfile.lock` to only the gems you wrote yourself. This naturally collapses Rails monorepo (12 sub-gems → one `rails` entry) and cuts typical output by ~50%. Use `--all` to include transitive dependencies:

```bash
postcut          # only direct deps (recommended)
postcut --all    # everything in Gemfile.lock — useful for security audits
```

## How it works

```
Gemfile        ─► direct deps (default scope)
Gemfile.lock   ─► installed versions
models.dev     ─► your model's training cutoff
RubyGems API   ─► all versions + dates
                  ▼
       per gem, four enrichment layers:
       1. GitHub /releases  ─► curated release notes
       2. CHANGELOG.md raw  ─► fallback for ankane/dhh-style maintainers
       3. regex CVE-NNNN    ─► fast detection from release body
       4. GitHub Advisories ─► structured CVE + severity + summary
                  ▼
              clean string to stdout
```

Output budget for a typical Rails app: 1–3k tokens with `--all`, 500–1500 tokens with default direct-only filter.

## Status

`v0.2-dev`. Ruby (`Gemfile.lock`) only. Multi-language adapters (npm / pypi / cargo / go) coming in v0.3+. No cache yet — first run hits the network, takes ~30–90s for a typical Rails app. With `GITHUB_TOKEN` set, well within rate limits.

## License

MIT
