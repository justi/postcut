# postcut

> **Stop Claude from hallucinating on your Gemfile.**
> postcut diffs your `Gemfile.lock` against the model's training cutoff and writes a markdown brief you paste into the chat. CVEs, breaking changes, version deltas — what Claude, GPT, or whatever coding model you use doesn't know yet.

## What it generates

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

**8.1.2 (last seen) → 8.1.3 (current, 2026-03-24) | project: 8.1.2**

- [activerecord] 8.1.3: Fix `insert_all` log message; Restore previous instrumenter
- [actionview] 8.1.3: Fix encoding errors for non-ASCII string locals
- 8.1.3: GHSA-h4wq-7r2x-9j3p [medium] CVE-2026-12104: SQL injection via deprecated query API
```

`cat .postcut/claude-opus-4-7.md | pbcopy` → paste into Claude → it sees the 8.1.3 patch and the CVE before it touches your code.

## Why this exists

LLM training cutoffs lag 3–12 months. Your `Gemfile.lock` doesn't. The gap is where deprecated APIs and missed CVEs live — and the model will confidently reason from old knowledge unless you hand it the diff.

If you've ever caught Claude suggesting a method that no longer exists, or GPT recommending a gem version with an open advisory — that's the gap. postcut closes it in one bash command.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/justi/postcut/main/install.sh | bash
```

Installs to `~/.postcut`, symlinks into PATH. Re-run to update, or `postcut --update`.

Manual:

```bash
git clone https://github.com/justi/postcut.git ~/.postcut
ln -s ~/.postcut/bin/postcut /usr/local/bin/postcut
```

Requires `bash 3.2+`, `git`, `curl`, `jq`. Ruby (`Gemfile.lock`) only for now.

## Usage

```bash
cd my-rails-app
bundle install
postcut --model claude-opus-4-7   # writes .postcut/claude-opus-4-7.md
```

That's the whole first run. `cat .postcut/claude-opus-4-7.md | pbcopy`, paste into Claude, done.

Want multiple models per run (so you can pick whichever you actually have open)? Configure once at `~/.postcut/.config/models`:

```
claude-opus-4-7
claude-haiku-4-5
gpt-5
```

Then plain `postcut` produces `.postcut/claude-opus-4-7.md`, `.postcut/claude-haiku-4-5.md`, `.postcut/gpt-5.md`.

Other flags:

```bash
postcut --model claude-opus-4-7  # single model, skips config
postcut --since 2026-01-31       # explicit cutoff (skips models.dev lookup)
postcut --path ~/code/my-app     # run against a project other than cwd
postcut --all                    # include transitive deps
postcut --summary                # security/breaking/deprecation only — compact context
postcut --output my-context.md   # custom path (single model)
postcut --stdout                 # legacy plain-text pipe (`postcut --stdout | pbcopy`)
postcut --update                 # fast-forward the install dir
```

## Modes — local vs HTTP

postcut auto-detects the Ruby toolchain in `PATH` — no flag needed.

| Layer | Local source | HTTP fallback |
|---|---|---|
| Versions + dates | — (registry-only) | `rubygems.org/api/v1/versions` |
| Source URI | `gem specification <pkg>` | `rubygems.org/api/v1/gems` |
| Release notes | gem CHANGELOG.md from `gem env gemdir` — Rails meta-gem expands into the 12 sub-gem CHANGELOGs | GitHub Releases → raw CHANGELOG.md |
| CVE / security | `bundler-audit` + ruby-advisory-db | GitHub Advisories DB |

To engage everything:

```bash
gem install bundler-audit
bundle-audit update    # one-time, syncs the local CVE DB
```

Set `GITHUB_TOKEN` to lift the rate limit on registry/advisory calls (60/h → 5000/h).

## Status

`v0.3.1`. Ruby/Rails only — by design, for now. Dual-mode complete (metadata, notes, advisories). Save mode + per-model snapshot is the default; `--stdout` keeps the legacy pipe. ~205 bash tests, CI on every PR. I use postcut daily on a Rails 8 app — that's the smoke test that matters most to me.

## Why I built this

I was on a flight to Tokyo, no wifi, debugging a Rails 8.1 app with Claude. Three prompts in: model confidently called an API the latest patch had quietly changed. Fourth: a gem version with an open CVE I'd patched two days earlier. I spent the rest of the flight pasting CHANGELOGs from memory.

postcut runs once before the flight. The model gets the diff it didn't have. Same trick works on any LLM workflow — coding assistant, code review, refactor — anywhere stale dependency knowledge bites.

Solo project, MIT, scratching my own itch.

## Roadmap (and where I need help)

Same offline-prep flow, different lockfile:

- **Node.js** (`package-lock.json`, `pnpm-lock.yaml`) — adapter contract is in `lib/adapters/`. If you live in Node and want this, open an issue tagged `adapter:node` — I'll pair on it.
- **Python** (`uv.lock`, `poetry.lock`) — same deal.
- **Rust**, **Go** — further out.

The adapter surface is small — a lockfile parser plus three local/HTTP function pairs (metadata, notes, advisories), seven functions total. Fork-and-PR welcome.

## Community

- **Found a gem that doesn't expand correctly?** Open an issue with the `Gemfile.lock` line — I read every one.
- **Idea or use case I missed?** Open an issue tagged `enhancement`, or send a PR.
- **Built something on top of postcut?** I want to know.

## License

MIT
