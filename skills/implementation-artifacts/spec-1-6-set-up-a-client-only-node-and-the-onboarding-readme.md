---
token_cost: {input: 187658, output: 72492, cache_read: 7978824, total: 8238974}
final_revision: '8b15877e1bd0702f1fa10803d7ca989036b76c54'
title: 'Set up a client-only node and the onboarding README'
type: 'feature'
created: '2026-09-11'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '7540799937ab53601c6c30df4dbce4abce7e047d'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The public repo has no onboarding path for a client-only machine (macOS, native Windows, or WSL used purely to connect out) and no top-level index routing a stranger to the right node guide, so "clone the repo and onboard any node from the docs alone" (the epic's own success bar) is currently unreachable end to end.

**Approach:** Add `docs/node-client.md` covering macOS (Tailscale app or Homebrew), native Windows (Tailscale Windows app + built-in OpenSSH client; bash via Git Bash or WSL to run `doctor.sh`), and WSL as a client — each ending in `tailscale ssh`/`ssh` reaching a host. Rewrite `README.md` into the onboarding index: mesh overview, the four-layer model, prerequisites, a "pick your node type" table linking all four `docs/node-*.md` guides, and the existing public-repo rules.

## Boundaries & Constraints

**Always:** `docs/node-client.md` covers exactly three platforms (macOS, native Windows, WSL-as-client) using only `<node>`/`<user>`/`<workspace>`/`<distro>` placeholders. Each subsection sets `config/local.env` with `NODE_ROLE=client`, runs `./scripts/doctor.sh` and states host checks (`tailscale-ssh-advertised`, `workspaces-dir`, `platform-contract`) read `SKIP` while common checks (`tailscale-installed`, `tailnet-membership`, `tmux-installed`, `claude-installed`, `git-installed`, `ssh-dir-perms`, `ssh-key-perms`) read `PASS` (`run_host_checks` client branch, `doctor.sh:313`-`317`), then ends with `tailscale ssh <user>@<node>` (or `ssh <user>@<node>` fallback) reaching a host and the same check-mode re-auth explanation used in `node-linux.md`. `README.md` becomes the onboarding index: what the mesh is, the four-layer model table (L1 Network+identity / L2 Transport+auth / L3 Persistence / L4 Agent, from the architecture spine), prerequisites, a routing table linking `node-linux.md`/`node-macos.md`/`node-wsl.md`/`node-client.md`, and the current public-repo-rules/hygiene-gates content preserved.

**Ask First:** None expected — documentation-only story; `doctor.sh`'s client-role branch already ships from story 1.2.

**Never:** Modify `scripts/doctor.sh` or any other script. Write host-enrollment steps into `docs/node-client.md` (hosts are already covered by `node-linux.md`/`node-macos.md`/`node-wsl.md`). Claim to have executed a live timed onboarding on real second hardware — this agent has none; instead record a step-count-based time estimate against `docs/node-client.md`'s own steps in the Verification notes, explicitly flagged as an estimate, mirroring the doctor.sh-all-clear-as-proxy precedent already used in `node-wsl.md`/`node-macos.md` for checks this agent can't physically run. Commit a real hostname/IP/ACL policy file/auth key.

</frozen-after-approval>

## Code Map

- `docs/node-client.md` -- new file, the guide (AC target path, epics.md Story 1.6).
- `docs/node-linux.md` -- Conventions block, doctor.sh-verification wording, tailnet-ACL/cross-node/check-mode-re-auth sections to mirror.
- `docs/node-macos.md` -- GUI-app-vs-Homebrew wording pattern; client doc allows either freely since client role never triggers `platform-contract`.
- `docs/node-wsl.md` -- WSL distro-pick and Tailscale-in-distro install steps to reuse for the WSL-client subsection (skip systemd/platform-contract, client role SKIPs it).
- `scripts/doctor.sh` -- read-only: `run_common_checks` (`doctor.sh:208`, any role), `run_host_checks` client branch (`doctor.sh:306`, SKIPs host checks for `client`), `resolve_and_validate_role` (`doctor.sh:89`).
- `config/local.env.example` -- reference for `NODE_ROLE=client`.
- `README.md` -- rewrite target.
- `skills/planning-artifacts/architecture/architecture-agentic-workstation-2026-09-10/ARCHITECTURE-SPINE.md:22-31` -- source of the four-layer model table (L1-L4) the README must state.
- `.gitleaks.toml` -- read-only; confirms placeholder tokens already allowlisted.

## Tasks & Acceptance

**Execution:**
- [x] `docs/node-client.md` -- write macOS-client subsection (Tailscale app or Homebrew, either fine for client role) -- FR14, AC1
- [x] `docs/node-client.md` -- write native-Windows-client subsection (Tailscale Windows app + built-in OpenSSH client; bash via Git Bash or WSL to run `doctor.sh`) -- FR14, AC1
- [x] `docs/node-client.md` -- write WSL-client subsection (Tailscale inside distro; no systemd/platform-contract requirement) -- FR14, AC1
- [x] `docs/node-client.md` -- each subsection: `config/local.env` `NODE_ROLE=client` -> `doctor.sh` (host checks SKIP, common checks PASS) -> `tailscale ssh <user>@<node>`/`ssh` reaching a host + check-mode re-auth note -- AC1, AC2
- [x] `README.md` -- rewrite as onboarding index: mesh overview, four-layer model table, prerequisites, "pick your node type" table (all four guides), public-repo rules preserved -- NFR3, AC3
- [x] `docs/node-client.md` -- Verification section: step-count time estimate against the guide's own steps, flagged as an estimate (no live second machine in this headless run) -- M3, NFR6, AC4

**Acceptance Criteria:**
- Given `docs/node-client.md`, when followed for macOS, native Windows, or WSL, then each path ends with `tailscale ssh <user>@<node>` (or `ssh`) reaching a host and documents check-mode re-auth (FR14).
- Given `config/local.env` with `NODE_ROLE=client`, when `doctor.sh` runs, then host checks read `SKIP` and common checks read `PASS`.
- Given `README.md`, then it is the onboarding index: mesh overview, four-layer model, prerequisites, node-type routing table, public-repo rules (NFR3).
- Given a person with only the README, when they onboard one node type end to end, then the guide's own step count stays well under 30 minutes and touches no other node — recorded as an estimate, not a live test (M3, NFR6).
- Given all docs, when gitleaks/grep run for `100\.`, `fd7a:`, and real hostnames/usernames, then nothing is found (FR13).

## Design Notes

Client role never calls `check_platform_contract` (`run_host_checks` SKIPs all three host-only checks for `client`, `doctor.sh:313`-`317`), so `node-client.md` needs none of the daemon-service maneuvering the host guides require (no Homebrew-vs-GUI-app forcing on macOS, no systemd dance on WSL) — client subsections can point at each platform's simplest official install path. Windows-native is the one client subsection with no host-guide precedent to mirror: Tailscale itself installs as the native Windows app, but `doctor.sh` is a bash script, so it needs Git Bash or a WSL shell purely to run the readiness check — the guide must be explicit that these are two independent things.

## Verification

**Commands:**
- `gitleaks git` (or the pre-commit hook) -- expected: zero findings on `docs/node-client.md` and `README.md`.
- `grep -rEn '100\.[0-9]+\.[0-9]+\.[0-9]+|fd7a:' docs/node-client.md README.md` -- expected: no matches.

**Manual checks (if no CLI):**
- `docs/node-client.md` covers exactly macOS, native Windows, and WSL, uses only placeholders, and every command block is copy-pasteable as written.
- Cross-check each doctor.sh-related claim (which checks PASS/SKIP for `client`) against `scripts/doctor.sh:306`-`319`.
- `README.md`'s routing table links all four existing `docs/node-*.md` files and its four-layer-model row order matches `ARCHITECTURE-SPINE.md:24`-`29`.

## Suggested Review Order

**Onboarding index (entry point)**

- New "What this is" / four-layer model / prerequisites / routing table, replacing the bare public-repo-rules-only README.
  [`README.md:5`](../../README.md#L5)

- Four-layer table mirrors `ARCHITECTURE-SPINE.md:24`-`29` verbatim, with a footnote clarifying which script paths don't exist yet (Epic 2/3).
  [`README.md:24`](../../README.md#L24)

- "Pick your node type" routing table links all four `docs/node-*.md` guides plus a one-line note on `NODE_ROLE=both`.
  [`README.md:58`](../../README.md#L58)

**Client enrollment path (`docs/node-client.md`)**

- macOS: either the GUI app or Homebrew works, since client role never triggers `platform-contract` — the key divergence from the macOS *host* guide.
  [`node-client.md:25`](../../docs/node-client.md#L25)

- Native Windows: the Tailscale app and the bash shell running `doctor.sh` are deliberately framed as two independent things.
  [`node-client.md:137`](../../docs/node-client.md#L137)

- WSL-as-client: no `systemd`/`[boot]` maneuvering needed, unlike `node-wsl.md`'s host enrollment — the distro's default init is fine.
  [`node-client.md:269`](../../docs/node-client.md#L269)

**`doctor.sh` client-branch contract (all three platforms)**

- `run_host_checks`'s `client` case (`scripts/doctor.sh:313`-`317`) SKIPs all host-only checks unconditionally — cited consistently across all three platform sections post-review.
  [`node-client.md:112`](../../docs/node-client.md#L112)

**Post-review patches**

- Tailscale version-floor check (`>=1.102.0`) added to macOS and native-Windows sections to match the WSL section's existing check.
  [`node-client.md:54`](../../docs/node-client.md#L54)

- `tailscaled`/`tailscale up` startup race and idempotent restart guarded with a `pgrep` check and a readiness-wait loop.
  [`node-client.md:322`](../../docs/node-client.md#L322)

- Verification section's estimate reworded to drop first-person "this agent" phrasing and internal requirement-ID citations.
  [`node-client.md:416`](../../docs/node-client.md#L416)

**Peripherals**

- Conventions block, including the `<distro>` placeholder unique to the WSL-as-client section.
  [`node-client.md:13`](../../docs/node-client.md#L13)
