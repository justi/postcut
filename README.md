# postcut

> Offline-prep dependency context for your LLM. Run before you fly; `cat` the doc into your chat session at 35,000 ft.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/justi/postcut/main/install.sh | bash
```

Clones to `~/.postcut`, symlinks `bin/postcut` into the first writable bin dir on your PATH (`/usr/local/bin`, `~/.local/bin`, `~/bin`), seeds `~/.postcut/.config/models` with a commented template, and smoke-tests `postcut --version`. Re-running pulls the latest changes and keeps your edits to the config file.

If `gh` is authenticated, the installer prints (does not write) the `GITHUB_TOKEN` export line you can drop into your shell rc to lift the GitHub rate limit (60/h → 5000/h).

Manual install:

```bash
git clone https://github.com/justi/postcut.git ~/.postcut
ln -s ~/.postcut/bin/postcut /usr/local/bin/postcut
```

Requires `bash 3.2+`, `git`, `curl`, `jq`. Ruby (`Gemfile.lock`) only for now.

## Usage

```bash
cd my-rails-app
bundle install
postcut                # writes .postcut/<model>.md per model
```

Default flow: postcut reads the model list from `~/.postcut/.config/models` (one model id per line). For each, it resolves the cutoff via models.dev, walks your `Gemfile.lock`, and writes a markdown document to `.postcut/<model>.md` — self-contained, ready to paste.

Sample document:

```markdown
# postcut — my-rails-app

| Field | Value |
|---|---|
| Generated | 2026-05-08 |
| Model | `claude-opus-4-7` |
| Cutoff | 2026-01-31 (source: models.dev/claude-opus-4-7) |
| Scope | 32 direct deps (Gemfile) |
| Updates | 8 gem(s) post-cutoff |

## Dependency deltas

### rails

**8.1.2 (last seen) → 8.1.3 (current, 2026-03-24)**

- [activerecord] 8.1.3: Fix `insert_all` log message; Restore previous instrumenter
- [actionview] 8.1.3: Fix encoding errors for non-ASCII string locals
- 8.0.2.1: GHSA-76r7-hhxj-r776 [medium] CVE-2025-55193: ANSI escape injection

### rake
...
```

Configure your models once (`~/.postcut/.config/models`):

```
claude-opus-4-7
claude-haiku-4-5
gpt-5
```

Then `postcut` produces `.postcut/claude-opus-4-7.md`, `.postcut/claude-haiku-4-5.md`, `.postcut/gpt-5.md` — pick whichever model you actually run with.

In flight, no internet:

```bash
cat .postcut/claude-opus-4-7.md | pbcopy   # paste into Claude
cat .postcut/gpt-5.md                      # or read it yourself
```

```bash
postcut --model claude-opus-4-7  # single model, skips config
postcut --since 2026-01-31       # explicit cutoff (skips models.dev lookup)
postcut --all                    # include transitive deps
postcut --summary                # security/breaking/deprecation only — compact context
postcut --output my-context.md   # custom path (single model)
postcut --stdout                 # legacy plain-text pipe (`postcut --stdout | pbcopy`)
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

`v0.3.0`. Ruby only. Dual-mode complete (metadata, notes, advisories).
Save mode + per-model snapshot is the default; `--stdout` keeps the
legacy pipe. CI on every PR (GitHub Actions, full bash suite).

Roadmap: Node.js, Python, Rust, Go adapters. Same offline-prep flow,
different lockfile.

## License

MIT
