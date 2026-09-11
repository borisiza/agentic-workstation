---
token_cost: {input: 98733, output: 34754, cache_read: 2813625, total: 2947112}
final_revision: '5aea2fe4d07c8a0fd74d03100c983c978c25a17e'
title: 'Publishable repo skeleton with hygiene gates'
type: 'feature'
created: '2026-09-10'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '27328fba06360d295fd544e5c4ec2baf82869724'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The product repo (this repo, doubling as the public mesh repo) has no source tree, no secret-leak protection, and no lint gate yet — anything committed today could leak a real host name, key, or token, and later stories have nowhere to put their scripts.

**Approach:** Scaffold the exact directories from the architecture source tree (`scripts/`, `config/`, plus the existing `docs/`), add a `.gitleaks.toml` allowlist + `.pre-commit-config.yaml` gitleaks hook for local commits, a `.github/workflows/hygiene.yml` CI job running shellcheck + gitleaks over full history, extend `.gitignore` for the remaining product secret patterns, and add a `README.md` stub stating the public-repo rules.

## Boundaries & Constraints

**Always:** Empty dirs (`scripts/`, `config/`) get a `.gitkeep`. `.gitleaks.toml` allowlists only the literal placeholder tokens `<node>`, `<user>`, `<workspace>`, `<distro>`. Pin gitleaks 8.30.1 and shellcheck 0.11.0 exactly (pre-commit hook `rev` and CI action version). `.gitignore` gains `config/local.env`, `authorized_keys`, and `docs/discovery/` alongside the existing secret patterns (`*.key`, `*.pem` already present) — do not touch or reorder existing unrelated entries in this file. `hygiene.yml` triggers on push and pull_request, runs shellcheck over `scripts/*.sh` (none exist yet — job must still pass with zero matches) and `gitleaks/gitleaks-action` over full git history, red on any finding. README states: placeholders only, no host list, personal values only in untracked `config/local.env`.

**Ask First:** Any change to already-existing, unrelated `.gitignore` entries (the current BMAD-tooling ignores) beyond appending the three new product patterns.

**Never:** Do not create `scripts/*.sh`, `config/local.env.example`, or any doctor/connect script — those belong to Story 1.2+. Do not commit any real secret, host name, or tailnet identifier anywhere (including as a gitleaks test fixture — use the tool's own built-in test pattern, don't hand-craft one containing a real-looking token).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fresh clone tree check | `git clone` then `ls` | `scripts/`, `config/`, `docs/`, `.github/workflows/hygiene.yml`, `.gitleaks.toml`, `.pre-commit-config.yaml`, `.gitignore`, `README.md` all present | N/A |
| Gitignore blocks product secrets | create `config/local.env`, `foo.key`, `foo.pem`, `authorized_keys`, `docs/discovery/x.md`, `x.log`; `git status` | none appear as untracked | N/A |
| Pre-commit blocks a real finding | `pre-commit install`; stage a file with gitleaks' own test secret pattern; commit | commit blocked, finding printed | gitleaks exits non-zero, pre-commit aborts commit |
| Pre-commit allows placeholders | stage a doc containing only `<node>`, `<user>`, `<workspace>`, `<distro>` | commit succeeds | N/A |
| CI hygiene gate | push/PR | `hygiene.yml` runs shellcheck 0.11.0 + gitleaks-action over full history; red on any finding, green otherwise | job fails the check on any finding |
| Full-history baseline | `gitleaks git` on repo history | zero findings | N/A |

</frozen-after-approval>

## Code Map

- `.gitignore` -- existing meta/BMAD-tooling ignore file at repo root; already covers `*.key`, `*.pem`, `*.env`/`.env.*` — append `config/local.env`, `authorized_keys`, `docs/discovery/` without disturbing existing sections.
- `docs/` -- already exists (holds `docs/product/poc-plan.md`); no `.gitkeep` needed, satisfies the AC's tree-listing check as-is.
- `scripts/.gitkeep`, `config/.gitkeep` -- new, empty placeholders per architecture source tree.
- `.gitleaks.toml` -- new, allowlist for the four placeholder tokens.
- `.pre-commit-config.yaml` -- new, single repo entry: `gitleaks/gitleaks` pinned `rev: v8.30.1`, hook id `gitleaks`.
- `.github/workflows/hygiene.yml` -- new, one job: checkout (full history, `fetch-depth: 0`), `shellcheck` 0.11.0 over `scripts/*.sh` (glob-safe when empty), `gitleaks/gitleaks-action` pinned to the release matching gitleaks 8.30.1.
- `README.md` -- new stub: project one-liner + public-repo rules section (placeholders only, no host list, secrets only in untracked `config/local.env`).

## Tasks & Acceptance

**Execution:**
- [x] `scripts/.gitkeep`, `config/.gitkeep` -- create empty dirs -- match architecture source tree
- [x] `.gitignore` -- append `config/local.env`, `authorized_keys`, `docs/discovery/` -- close the remaining AC-11 gaps without touching existing entries
- [x] `.gitleaks.toml` -- allowlist regex for `<node>|<user>|<workspace>|<distro>` -- FR12 placeholder exception
- [x] `.pre-commit-config.yaml` -- gitleaks hook pinned v8.30.1 -- FR12 local gate
- [x] `.github/workflows/hygiene.yml` -- shellcheck 0.11.0 + gitleaks-action, push+PR triggers, full-history checkout -- FR11–14 CI gate
- [x] `README.md` -- public-repo rules stub -- M2 baseline doc requirement

**Acceptance Criteria:**
- Given a fresh clone, when the tree is listed, then all required paths exist and empty dirs carry `.gitkeep`.
- Given the committed `.gitignore`, when the six probe files are created, then `git status` shows none of them untracked.
- Given `pre-commit install`, when a fake secret is staged, then the commit is blocked with the finding printed; when only placeholders are staged, the commit passes.
- Given a push or PR, when CI runs, then `hygiene.yml` is red on any shellcheck or gitleaks finding.
- Given `README.md`, then it documents the public-repo rules and `gitleaks git` over full history reports zero findings.

## Design Notes

Gitleaks fixture for the "blocked" test case: use `pre-commit run --all-files` locally with a scratch file containing gitleaks' own documented test-detection string (e.g. a generic high-entropy AWS-style key from gitleaks' own test fixtures), never a bespoke string that looks like a real project secret — delete the scratch file after verifying, never commit it.

## Verification

**Commands:**
- `pre-commit run --all-files` -- expected: passes on clean tree, blocks on injected fake secret
- `gitleaks git . -v` -- expected: zero findings on full history (8.30.1 has no `--source` flag; the path is positional)
- `shellcheck scripts/*.sh` -- expected: passes vacuously (no `.sh` files yet) or clean
- `git status` after creating the six AC-11 probe files -- expected: no new untracked entries

## Suggested Review Order

**CI hygiene gate**

- Entry point — the CI job that gates every push/PR on shellcheck + gitleaks findings.
  [`hygiene.yml:1`](../../.github/workflows/hygiene.yml#L1)

- Gitleaks scans full history via `fetch-depth: 0`; version pinned separately from the action tag.
  [`hygiene.yml:37`](../../.github/workflows/hygiene.yml#L37)

- Shellcheck install is version-pinned and glob-safe (`nullglob`) so it passes vacuously with no `.sh` files yet.
  [`hygiene.yml:16`](../../.github/workflows/hygiene.yml#L16)

**Local pre-commit gate**

- Mirrors the CI gitleaks check locally, pinned to the same `v8.30.1`.
  [`.pre-commit-config.yaml:1`](../../.pre-commit-config.yaml#L1)

**Secret allowlist**

- Extends gitleaks' default ruleset with a narrow allowlist for the four literal placeholder tokens only.
  [`.gitleaks.toml:5`](../../.gitleaks.toml#L5)

**Gitignore and docs**

- Appends the three remaining product secret patterns without touching existing sections.
  [`.gitignore:29`](../../.gitignore#L29)

- States the public-repo placeholder rule and where the hygiene gates live.
  [`README.md:5`](../../README.md#L5)

**Peripherals**

- Empty placeholders matching the architecture source tree.
  [`scripts/.gitkeep`](../../scripts/.gitkeep), [`config/.gitkeep`](../../config/.gitkeep)

- Story status lifted to `in-progress` (epic lift included).
  [`sprint-status.yaml:37`](sprint-status.yaml#L37)

