# postcut

> **Stop your LLM from hallucinating on your Gemfile.**
> postcut diffs your `Gemfile.lock` against the model's training cutoff and writes a markdown brief you paste into the chat. CVEs, breaking changes, version deltas — what your local Qwen, your hosted Claude, GPT, or whatever coding model you use doesn't know yet.

## What it generates

```markdown
# postcut — my-rails-app

| Field | Value |
|---|---|
| Generated | 2026-05-11 |
| Model | `qwen3.6-35b-a3b` |
| Cutoff | 2025-04-15 (source: --since) |
| Scope | 32 direct deps (Gemfile) |
| Updates | 14 gem(s) post-cutoff |

## Dependency deltas

> Each section below describes how a gem changed since the model's training cutoff.
> Use the post-cutoff version's API; flag breaking-change versions explicitly.

### rails

**8.0.2 (last seen) → 8.1.3 (current, 2026-03-24) | project: 8.1.2**

- 8.0.3: PostgreSQL adapter timezone regression fix; security backport for `params.permit`
- 8.1.0: **Breaking** Active Job uses Solid Queue by default in new apps; legacy adapters opt-in
- 8.1.0: composite primary keys promoted from edge to core
- [activerecord] 8.1.3: Fix `insert_all` log message; Restore previous instrumenter
- 8.1.2: GHSA-XXXX-XXXX-XXXX [medium] CVE-2026-XXXXX: <real advisory note from ruby-advisory-db / GitHub Advisories>
```

`cat .postcut/qwen3.6-35b-a3b.md | pbcopy` → paste into your local model → done arguing about Rails 8.0 patterns on a Rails 8.1 app.

## Why this exists

LLM training cutoffs lag 3–12 months. Your `Gemfile.lock` doesn't. The gap is where deprecated APIs and missed CVEs live — and the model will confidently reason from old knowledge unless you hand it the diff.

If you've ever caught a local coder model proposing Rails 8.0 patterns on a Rails 8.1 app, or any LLM recommending a gem version with an open advisory — that's the gap. postcut closes it in one bash command, before you lose internet.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/justi/postcut/main/install.sh | bash
```

Installs to `~/.postcut` and symlinks into PATH when it finds a writable bin dir (otherwise the installer prints an `export PATH=...` line you can drop into your shell rc). Re-run to update, or `postcut --update`.

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
postcut --model qwen3.6-35b-a3b --since 2025-04-15   # writes .postcut/qwen3.6-35b-a3b.md
```

That's the whole first run. `cat .postcut/qwen3.6-35b-a3b.md | pbcopy`, paste into your local model (ollama, llama.cpp, LM Studio — whatever you run), done.

`--since` is needed when models.dev doesn't yet have your model's cutoff. For models it does know (e.g. `claude-opus-4-7`, `gpt-5`), drop `--since` and let postcut resolve.

Want multiple models per run (one for the flight, one for when you have wifi)? Configure once at `~/.postcut/.config/models`:

```
qwen3.6-35b-a3b
codestral-22b
claude-opus-4-7
```

Then plain `postcut` produces `.postcut/qwen3.6-35b-a3b.md`, `.postcut/codestral-22b.md`, `.postcut/claude-opus-4-7.md` — pick whichever you actually have running.

Other flags:

```bash
postcut --model qwen3.6-35b-a3b  # single model, skips config
postcut --since 2025-04-15       # explicit cutoff (skips models.dev lookup)
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

Set `GITHUB_TOKEN` to lift the rate limit on release-notes/advisory calls (60/h → 5000/h). RubyGems registry calls are unauthenticated.

## Status

`v0.3.1`. Ruby/Rails only — by design, for now. Dual-mode complete (metadata, notes, advisories). Save mode + per-model snapshot is the default; `--stdout` keeps the legacy pipe. ~205 bash tests, CI on every PR. I use postcut daily on a Rails 8 app — that's the smoke test that matters most to me.

## Why I built this

I was on a flight to Tokyo, no wifi, debugging a Rails 8.1 app with qwen3.6-35b-a3b running locally via ollama. Three prompts in: model confidently called an API from Rails 8.0 — its training had ended thirteen months earlier, before the 8.1 release. Fourth: a gem version with an open CVE I'd patched two days earlier. I spent the rest of the flight pasting CHANGELOGs from memory.

postcut runs once before the flight, while you still have internet. The model gets the diff it didn't have. Same trick works for hosted models too — you just stop wasting tokens correcting the same stale-knowledge mistakes — but offline is where it actually saves the session.

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
