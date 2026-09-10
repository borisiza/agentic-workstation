---
stepsCompleted: [1, 2, 3, 4]
inputDocuments:
  - skills/planning-artifacts/prds/prd-agentic-workstation-2026-09-10/prd.md
  - skills/planning-artifacts/prds/prd-agentic-workstation-2026-09-10/addendum.md
  - skills/planning-artifacts/architecture/architecture-agentic-workstation-2026-09-10/ARCHITECTURE-SPINE.md
---

# agentic-workstation - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for agentic-workstation, decomposing the requirements from the PRD, UX Design if it exists, and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

**F1. SSH access between nodes**

FR1: Host nodes accept SSH connections authenticated exclusively by Tailscale SSH (tailnet identity, ACL `check` mode re-auth); no password, no root login, no sshd of their own on the primary path.
FR2: A documented, repeatable per-node setup (script or guide) joins the node to the tailnet and, for hosts, advertises Tailscale SSH (`tailscale up --ssh`) — without ever committing tokens, auth keys, or key material.
FR3: Connectivity runs over the Tailscale tailnet only; no ports exposed to the public internet.
FR15: Key material and local session-state files carry restrictive permissions (0600 files / 0700 dirs), verified by `doctor.sh`.
FR17: Each node declares its role (`host`, `client`, `both`) in a gitignored local config (`config/local.env`); scripts read the role from there, never from committed files.
FR18: Fallback path: a host that cannot run the Tailscale SSH server exposes OpenSSH reachable only over the tailnet, key-only (ed25519, one key per client machine, never copied between machines), password and root login disabled; `scripts/enroll.sh` installs a client's public key on that host. Opt-in per host (`FALLBACK_SSHD=1`), documented as the exception.

**F2. Run Claude Code remotely**

FR4: From any client node, the user reaches a host and lands in Claude Code inside a chosen workspace with one command (`scripts/connect.sh <node> <workspace>`); on the host itself the equivalent is `scripts/start-claude.sh <workspace>`.
FR5: Claude Code runs with the project's normal permission mode — no `--dangerously-skip-permissions` bypass. Approvals happen in the remote terminal.
FR16: A session operates only inside its workspace directory (allowlist); it must not touch sibling workspaces.

**F3. Persistent sessions**

FR6: Claude Code runs inside a persistent multiplexer session (tmux, confirmed by AD-4) so a dropped SSH connection does not kill it.
FR7: Reattaching (`scripts/status.sh` to list, then attach) restores the running session with scrollback.
FR8: Sessions are namespaced per host and named `claude-<workspace>`; simultaneous A→B and B→A sessions never collide. Session metadata (id, name, workspace, status, startedAt) contains no sensitive values and is gitignored if it lives inside the repo tree (AD-4/Deferred: tmux itself is the metadata store for MVP, no extra file).

**F4. Operability scripts**

FR9: `scripts/doctor.sh` verifies prerequisites (tailscale + tailnet membership, `--ssh` advertised on hosts, tmux, claude, git) and reports gaps without printing secrets or node names.
FR10: `scripts/start-claude.sh`, `status.sh`, `stop.sh` cover the session lifecycle on a host; `scripts/connect.sh` is the client side (lists reachable hosts from `tailscale status`, then attaches); `scripts/enroll.sh` exists only for the FR18 fallback.

**F5. Public-repo hygiene**

FR11: `.gitignore` excludes keys, tokens, session state, logs, node role config, and any machine-inventory output (e.g. `docs/discovery/`).
FR12: A pre-commit secret scan (gitleaks) blocks accidental secret commits.
FR13: Docs use placeholders (`<node>`, `<user>`, `<workspace>`, `<distro>`) — real hostnames, IPs, usernames and Tailscale node names never appear in committed files; there is no host list in the repo, discovery is `tailscale status`.
FR14: Setup docs cover every supported node type: hosts on macOS (open-source `tailscaled`), Linux, and Windows via WSL2 (WSL distro as its own tailnet node); clients on macOS, native Windows, and WSL.

### NonFunctional Requirements

NFR1: Security is the hard constraint: identity- or key-only SSH, no public port exposure, no privileged execution, logs free of tokens.
NFR2: Reconnection after a network drop takes under a minute and loses no session state; a reconnect that exceeds this or loses state is a defect, not an accepted limitation.
NFR3: Setup is reproducible by a stranger from the README alone, on any supported host type (macOS, Linux, Windows/WSL2) plus any supported client.
NFR4: Everything in the repo works with placeholder config; personal values live only in untracked local files (`config/local.env`, gitignored) or the macOS Keychain.
NFR5: The Git remote (GitHub) is the backup — work lands on pushed branches; third-party tools/scripts are reviewed before adoption.
NFR6: The mesh scales by addition only: onboarding node N+1 changes nothing on nodes 1..N (no key redistribution, no config edits, no registry update).

### Additional Requirements

**Starter template:** none. Greenfield bash repo; the architecture fixes the source tree (`scripts/`, `config/`, `docs/`, `.github/workflows/hygiene.yml`, `.gitleaks.toml`, `.pre-commit-config.yaml`, `.gitignore`). Epic 1 Story 1 must lay down this skeleton.

- AD-1 Role gating: `config/local.env` (gitignored) declares `NODE_ROLE=host|client|both`; client verbs (`connect.sh`) require `client|both`, host verbs (`start-claude.sh`, `status.sh`, `stop.sh`, `enroll.sh`) require `host|both`; any other combination exits 2 with one line on stderr. Repo path on every node is `$HOME/agentic-workstation`.
- AD-2 Addressing: peers addressed only by MagicDNS node name; tailnet IPs (`100.x`, `fd7a:`) never appear in scripts or docs; nothing listens on or forwards a non-tailnet interface.
- AD-3 Fallback contract: `FALLBACK_SSHD=1` opts a host into OpenSSH-over-tailnet with `PasswordAuthentication no`, `PermitRootLogin no`, `KbdInteractiveAuthentication no`, `AllowUsers <user>`; the client selects it explicitly with `connect.sh --fallback <node> <workspace>` using its own untracked `~/.ssh/config` entry; `connect.sh` never probes or keeps a list of fallback hosts. No ACL policy file committed.
- AD-4 Session contract: exactly one tmux session `claude-<workspace>` per workspace on the host's own tmux server, created with `tmux new -A -s claude-<workspace>` (idempotent attach-or-create); Claude launched as `claude -n claude-<workspace>`; host-reboot recovery is `claude --resume claude-<workspace>` (documented, not scripted); only `stop.sh` kills a session, one named session only (no wildcard, no `kill-server`).
- AD-5 Platform contract: supported hosts are exactly Linux (`tailscaled` service), macOS (open-source `tailscaled` via Homebrew formula + `brew services`, replacing the GUI app), Windows via one WSL2 distro as its own tailnet node (`/etc/wsl.conf` `[boot] systemd=true`, `tailscaled` under systemd). WSL hosts additionally need, outside the repo: `.wslconfig` `vmIdleTimeout=-1` + `instanceIdleTimeout=-1`, an at-logon Task Scheduler entry `wsl.exe -d <distro> --exec sleep infinity`, no-sleep power settings. `doctor.sh` encodes this contract as checks.
- AD-6 Unprivileged execution: `start-claude.sh` launches `claude` with cwd = workspace and `--permission-mode default`; never `--dangerously-skip-permissions` or `--add-dir`; `connect.sh` refuses `SSH_USER=root`.
- AD-7 Hygiene gates: `.gitignore` excludes `config/local.env`, `*.key`, `*.pem`, `authorized_keys`, `docs/discovery/`, session metadata, logs; gitleaks 8.30.1 runs as pre-commit hook (`gitleaks git --pre-commit --staged`) and as GitHub Action (`gitleaks/gitleaks-action`) on every push/PR, CI red on any finding; `.gitleaks.toml` allowlists `<placeholder>` tokens; Claude Code transcripts stay in `~/.claude/` on the host.
- AD-8 Script contract: every script is `#!/usr/bin/env bash` + `set -euo pipefail`, bash 3.2 compatible (no associative arrays, no `${var,,}`), passes shellcheck 0.11.0 in CI, parses `tailscale status` text output (no `jq`, no Python), exposes `--check` (side-effect-free self-test) which `doctor.sh` aggregates. Runtime deps exactly: `tailscale`, `tmux`, `claude`, `git` (+ `ssh`/`sshd` on FR18 hosts). No shared shell library; scripts never depend on each other except `connect.sh` invoking `$HOME/agentic-workstation/scripts/start-claude.sh` on the host by absolute path.
- Naming: `<workspace>` = basename of the workspace directory, lowercase `[a-z0-9-]`, resolved on the host as `$WORKSPACES_DIR/<workspace>` (must already exist; scripts never create it).
- Config: `config/local.env` is `KEY=value` shell syntax with `NODE_ROLE`, `WORKSPACES_DIR` (default `$HOME/workspaces`), `FALLBACK_SSHD` (`0`/`1`), `SSH_USER`; committed twin `config/local.env.example`. Precedence: env file → environment → flags, later wins. Also committed: `config/ssh_config.example` (client `Host <node>` + `ServerAliveInterval 15` / `ServerAliveCountMax 3`) and `config/tmux.conf.example` (history-limit, mouse).
- Errors/logging: non-zero exit + one-line message on stderr; stdout only, no log files, no peer names or secrets.
- Docs set (per node type): `docs/node-linux.md`, `docs/node-macos.md`, `docs/node-wsl.md`, `docs/node-client.md`, `docs/fallback-openssh.md`, plus README sufficient for NFR3/M3 (< 30 min onboarding by a stranger).
- CI: GitHub Actions runs only shellcheck + gitleaks; never a tailnet. One environment (the owner's tailnet), no staging.
- Stack pins: Tailscale 1.102.3, tmux 3.7c, Claude Code ≥ 2.1.257, gitleaks 8.30.1, shellcheck 0.11.0, WSL ≥ 2.4.4 (verify `wsl --version` on the host).
- Manual recovery doc items (Deferred, document-only): `tailscale serve --tcp 2222 22` shim for the `tailscaled`-restart gap; `claude --resume claude-<workspace>` after a host reboot.
- Verification (success metrics): M1 bidirectional demo (A→B and B→A: start, kill link, reconnect, session intact); M2 gitleaks zero findings on full history; M3 new node onboarded from committed docs alone in < 30 min without touching other nodes.

### UX Design Requirements

Not applicable — the MVP is CLI-only (`.bmad-no-ui` marker set). No UX design contract exists.

### FR Coverage Map

FR1: Epic 1 - Tailscale SSH only on hosts (`tailscale up --ssh`, no sshd on the primary path)
FR2: Epic 1 - Per-node setup docs/steps joining the tailnet, no committed secrets
FR3: Epic 1 - Tailnet-only connectivity, no public ports
FR4: Epic 2 - `connect.sh <node> <workspace>` / `start-claude.sh <workspace>`
FR5: Epic 2 - `--permission-mode default`, no bypass
FR6: Epic 2 - tmux-hosted session survives disconnect
FR7: Epic 2 - `status.sh` list + reattach with scrollback
FR8: Epic 2 - `claude-<workspace>` naming per host, no collisions
FR9: Epic 1 - `doctor.sh` prerequisite checks, no secrets/node names in output
FR10: Epic 2 - start-claude/status/stop/connect lifecycle (`enroll.sh` → Epic 3)
FR11: Epic 1 - `.gitignore` for keys, tokens, state, logs, `local.env`, `docs/discovery/`
FR12: Epic 1 - gitleaks pre-commit + CI
FR13: Epic 1 - placeholder-only docs, no host list
FR14: Epic 1 - docs for Linux/macOS/WSL2 hosts and macOS/Windows/WSL clients
FR15: Epic 1 - 0600/0700 checks in `doctor.sh` (fallback key checks → Epic 3)
FR16: Epic 2 - session confined to its workspace cwd
FR17: Epic 1 - `NODE_ROLE` in gitignored `config/local.env`, role-gated verbs
FR18: Epic 3 - OpenSSH-over-tailnet fallback, `enroll.sh`, `connect.sh --fallback`

## Epic List

### Epic 1: Enroll a machine as a mesh node
Any of the owner's machines (Linux, macOS, Windows/WSL2, or a client-only PC) clones the public repo, declares its role, joins the tailnet with Tailscale SSH advertised, passes `doctor.sh`, and is reachable by `tailscale ssh` — with the repo publishable at every commit (gitignore, gitleaks pre-commit + CI, placeholders-only docs).
**FRs covered:** FR1, FR2, FR3, FR9, FR11, FR12, FR13, FR14, FR15, FR17
**Also covers:** NFR1, NFR3, NFR4, NFR6, M2, M3; AD-1, AD-2, AD-5, AD-7, AD-8. Includes the repo skeleton (Story 1.1).

### Epic 2: Run and resume Claude Code on any host from any node
From a client node, one command lands the user in Claude Code inside a workspace on a host, in normal permission mode; the session lives in tmux, survives a dropped link, and is listed/reattached/stopped with the host scripts — bidirectionally, without collisions.
**FRs covered:** FR4, FR5, FR6, FR7, FR8, FR10, FR16
**Also covers:** NFR2, M1; AD-4, AD-6. Depends on Epic 1 (role config + tailnet membership).

### Epic 3: Host over OpenSSH when Tailscale SSH isn't an option
A host that must keep the Tailscale GUI app (or otherwise can't serve Tailscale SSH) opts into hardened key-only OpenSSH over the tailnet; a client enrolls its own ed25519 key and connects with `connect.sh --fallback`, with `doctor.sh` verifying key hygiene.
**FRs covered:** FR18 (plus the `enroll.sh` part of FR10 and the key-permission part of FR15)
**Also covers:** AD-3 fallback contract. Depends on Epic 2 (`connect.sh`). Documented exception; the primary path closes without it.

## Epic 1: Enroll a machine as a mesh node

Any of the owner's machines (Linux, macOS, Windows/WSL2, or a client-only PC) clones the public repo, declares its role, joins the tailnet with Tailscale SSH advertised, passes `doctor.sh`, and is reachable by `tailscale ssh` — with the repo publishable at every commit.

### Story 1.1: Publishable repo skeleton with hygiene gates

As the repo owner,
I want the repository scaffolded with secret and lint gates from the first commit,
So that everything pushed to the public repo is safe to publish and every script is checked.

**Acceptance Criteria:**

**Given** a fresh clone
**When** I list the tree
**Then** it contains `scripts/`, `config/`, `docs/`, `.github/workflows/hygiene.yml`, `.gitleaks.toml`, `.pre-commit-config.yaml`, `.gitignore` and a `README.md` stub, matching the architecture source tree (empty dirs held by `.gitkeep`)

**Given** the committed `.gitignore`
**When** I create `config/local.env`, `foo.key`, `foo.pem`, `authorized_keys`, `docs/discovery/x.md`, `x.log` and run `git status`
**Then** none of them appear as untracked (FR11)

**Given** `pre-commit install` has been run
**When** I stage a file containing a fake secret (gitleaks test pattern)
**Then** the commit is blocked by gitleaks 8.30.1 with the finding printed (FR12)
**And** staging a doc containing only `<node>`, `<user>`, `<workspace>`, `<distro>` placeholders passes (`.gitleaks.toml` allowlist)

**Given** a push or PR
**When** CI runs
**Then** `hygiene.yml` runs shellcheck 0.11.0 over `scripts/*.sh` and `gitleaks/gitleaks-action` over full history, and the job is red on any finding

**Given** `README.md`
**Then** it states the public-repo rules (placeholders only, no host list, personal values only in untracked `config/local.env`)
**And** `gitleaks git` on the full repo history reports zero findings (M2 baseline)

### Story 1.2: Declare the node role and verify readiness with doctor.sh

As a node operator,
I want to declare my node's role in an untracked file and run one command that tells me what is missing,
So that I know the node is ready before I try to connect.

**Acceptance Criteria:**

**Given** the committed `config/local.env.example` (`NODE_ROLE`, `WORKSPACES_DIR` default `$HOME/workspaces`, `FALLBACK_SSHD=0`, `SSH_USER`)
**When** I copy it to `config/local.env` and set `NODE_ROLE=host`
**Then** `scripts/doctor.sh` reads the role from that file and nothing else (precedence env file → environment → flags) (FR17)

**Given** `config/local.env` is missing or `NODE_ROLE` is not `host|client|both`
**When** I run `doctor.sh`
**Then** it exits 2 with exactly one line on stderr naming the fix

**Given** any valid role
**When** I run `doctor.sh`
**Then** it reports one `PASS|FAIL|SKIP` line per check with a fix hint: `tailscale` installed (≥ 1.102) and tailnet membership (backend Running), `tmux`, `claude`, `git` present, `~/.ssh` is 0700 and every `~/.ssh/id_*` private key is 0600 (FR15)
**And** it exits 0 only when no check is FAIL

**Given** `NODE_ROLE=host|both`
**When** I run `doctor.sh`
**Then** it additionally verifies Tailscale SSH is advertised on this node, `$WORKSPACES_DIR` exists, the platform contract (macOS: open-source `tailscaled` is the active backend, not the GUI app; WSL: systemd is PID 1), and FAILs otherwise
**And** with `NODE_ROLE=client` those host checks are SKIP

**Given** any run
**Then** output never contains tokens, keys, tailnet IPs (`100.x`, `fd7a:`) or node names (FR9)

**Given** `doctor.sh --check`
**Then** it runs a side-effect-free self-test and exits 0
**And** for every other `scripts/*.sh` present it runs `<script> --check` and aggregates the result (absent scripts are skipped, not failed)
**And** the script is `#!/usr/bin/env bash` + `set -euo pipefail`, bash 3.2 compatible, shellcheck-clean, no `jq`/Python (AD-8)

### Story 1.3: Enroll a Linux host

As the owner onboarding a Linux machine,
I want a step-by-step guide that joins it to the tailnet as a Tailscale SSH host,
So that any other node can SSH in with tailnet identity only.

**Acceptance Criteria:**

**Given** a fresh supported Linux machine
**When** I follow `docs/node-linux.md`
**Then** I install tailscale 1.102.3 from the official package, run `tailscale up --ssh`, install `tmux`/`claude`/`git`, clone the repo to `$HOME/agentic-workstation`, create `config/local.env` with `NODE_ROLE=host`, create `$WORKSPACES_DIR`, and `scripts/doctor.sh` reports all PASS

**Given** the guide
**Then** it uses `<node>`/`<user>` placeholders only, contains no auth key (login via the URL printed by `tailscale up`), and states the tailnet default ACL (`autogroup:member → autogroup:self`, check mode) is sufficient — no policy file is committed (FR2, FR13)

**Given** the host is enrolled
**When** from another tailnet node I run `tailscale ssh <user>@<node>` (or plain `ssh <user>@<node>`)
**Then** I get a shell after the identity check, with no password or key prompt (FR1)
**And** the guide explains check-mode re-authentication (browser URL) when the check period expires

**Given** the enrolled host
**When** I run the documented verification (`ss -tlnp`)
**Then** no sshd listens on any non-tailnet interface, and password/root login are impossible on the primary path (FR3, NFR1)

**Given** the guide
**Then** it documents the `tailscaled`-restart caveat and the manual `tailscale serve --tcp 2222 22` recovery shim
**And** no step touches any other node (NFR6)

### Story 1.4: Enroll a macOS host

As the owner onboarding a Mac,
I want a guide that replaces the GUI Tailscale app with the open-source `tailscaled` and advertises Tailscale SSH,
So that the Mac serves as a host on the primary path.

**Acceptance Criteria:**

**Given** a Mac running the Standalone/App Store Tailscale app
**When** I follow `docs/node-macos.md`
**Then** I quit/uninstall the GUI app, install the Homebrew `tailscale` formula, start it with `brew services start tailscale`, run `tailscale up --ssh`, and the node shows Tailscale SSH advertised
**And** the guide states what is lost (menu-bar GUI) and notes that a key-only OpenSSH fallback exists for Macs that must keep the GUI (OQ7; the fallback guide itself is delivered in Epic 3)

**Given** the tailnet step is done
**When** I complete the remaining steps (clone to `$HOME/agentic-workstation`, `config/local.env` with `NODE_ROLE=host`, `$WORKSPACES_DIR`, `doctor.sh`)
**Then** `doctor.sh` reports all PASS, including the "open-source `tailscaled` is the active backend" check

**Given** the enrolled Mac
**When** another node runs `tailscale ssh <user>@<node>`
**Then** a shell opens with identity auth only
**And** macOS Remote Login is documented as not required (and verified off with `sudo lsof -iTCP -sTCP:LISTEN`) on the primary path

**Given** the guide
**Then** it notes bash 3.2 is sufficient, uses placeholders only, and touches no other node

### Story 1.5: Enroll a Windows host via WSL2

As the owner onboarding a Windows PC,
I want a guide that makes one WSL2 distro its own tailnet node with Tailscale SSH and keeps it alive unattended,
So that the PC serves as a host without native-Windows SSH.

**Acceptance Criteria:**

**Given** Windows with WSL ≥ 2.4.4 (verified with `wsl --version`)
**When** I follow `docs/node-wsl.md`
**Then** one distro is chosen, `/etc/wsl.conf` has `[boot] systemd=true`, after `wsl --shutdown` systemd is PID 1, tailscale is installed inside the distro with `tailscaled` enabled under systemd, and `tailscale up --ssh` makes the distro appear as its own tailnet node with its own MagicDNS name (OQ6)

**Given** the Windows side
**Then** the guide covers, outside the repo: `%UserProfile%\.wslconfig` with `[wsl2] vmIdleTimeout=-1` and `instanceIdleTimeout=-1`, an at-logon Task Scheduler entry `wsl.exe -d <distro> --exec sleep infinity`, and no-sleep power settings (AD-5)
**And** it flags the `instanceIdleTimeout` version requirement as an assumption to verify on the host

**Given** the Windows PC restarts and the user logs on
**When** no one touches the desktop
**Then** within a few minutes another node can `tailscale ssh <user>@<node>` into the distro (unattended reachability)

**Given** the distro
**When** I clone to `$HOME/agentic-workstation`, set `NODE_ROLE=host`, create `$WORKSPACES_DIR` and run `doctor.sh`
**Then** all checks PASS, including the WSL systemd check
**And** the guide states the Windows-side Tailscale app is optional (client role only), uses `<distro>`/`<node>`/`<user>` placeholders only, and touches no other node

### Story 1.6: Set up a client-only node and the onboarding README

As someone cloning the public repo,
I want a client guide for every supported platform and a README that routes me to the right node guide,
So that I can onboard any machine from the committed docs alone.

**Acceptance Criteria:**

**Given** `docs/node-client.md`
**Then** it covers macOS (Tailscale app or Homebrew), native Windows (Tailscale Windows app + built-in OpenSSH client; bash scripts via Git Bash or WSL), and WSL as a client, each ending with `tailscale ssh <user>@<node>` (or `ssh`) reaching a host and passing check-mode re-auth (FR14)

**Given** `config/local.env` with `NODE_ROLE=client`
**When** I run `doctor.sh`
**Then** host checks are SKIP and client checks PASS

**Given** `README.md`
**Then** it is the onboarding index: what the mesh is, the four-layer model, prerequisites, a "pick your node type" table linking `node-linux.md`, `node-macos.md`, `node-wsl.md`, `node-client.md`, and the public-repo rules (NFR3)

**Given** a person with only the README
**When** they onboard one supported node type end to end
**Then** it takes under 30 minutes and modifies nothing on any other node (M3, NFR6) — verified by a timed dry run recorded in the story notes without node names

**Given** all docs
**When** I run gitleaks and grep for `100\.`, `fd7a:` and real hostnames/usernames
**Then** nothing is found (FR13)

## Epic 2: Run and resume Claude Code on any host from any node

From a client node, one command lands the user in Claude Code inside a workspace on a host, in normal permission mode; the session lives in tmux, survives a dropped link, and is listed/reattached/stopped with the host scripts — bidirectionally, without collisions.

### Story 2.1: Start Claude Code in a persistent tmux session on the host

As a host operator,
I want one command that opens (or re-opens) Claude Code for a workspace inside a named tmux session,
So that the agent keeps running when my terminal goes away.

**Acceptance Criteria:**

**Given** `NODE_ROLE=host|both` and an existing `$WORKSPACES_DIR/<workspace>`
**When** I run `scripts/start-claude.sh <workspace>`
**Then** it runs `tmux new -A -s claude-<workspace>` whose command is `cd $WORKSPACES_DIR/<workspace> && claude -n claude-<workspace> --permission-mode default`, and I land in Claude Code with the workspace as cwd (FR4, FR5, FR8)

**Given** the tmux session `claude-<workspace>` already exists
**When** I run `start-claude.sh <workspace>` again
**Then** it attaches to the existing session (scrollback intact) and does not start a second Claude Code (AD-4 attach-or-create)

**Given** `<workspace>` is missing, contains characters outside `[a-z0-9-]`, or `$WORKSPACES_DIR/<workspace>` does not exist
**When** I run the script
**Then** it exits 2 with one line on stderr and creates nothing (scripts never create workspaces)

**Given** `NODE_ROLE=client`, or the script runs as root (EUID 0)
**When** I run the script
**Then** it exits 2 with one line on stderr (AD-1, AD-6)

**Given** the script source
**Then** it never passes `--dangerously-skip-permissions`, `bypassPermissions` or `--add-dir` (FR5, FR16), exposes `--check` (side-effect-free self-test that `doctor.sh` aggregates), and conforms to AD-8 (bash 3.2, `set -euo pipefail`, shellcheck-clean, no `jq`)

### Story 2.2: List and stop workspace sessions on the host

As a host operator,
I want to see which Claude sessions are running on this host and stop exactly one of them,
So that I can find a session to reattach and never kill the wrong one.

**Acceptance Criteria:**

**Given** zero or more `claude-*` tmux sessions on this host
**When** I run `scripts/status.sh`
**Then** it prints one line per `claude-<workspace>` session with workspace name, attached/detached state and creation time, derived from `tmux ls` only (no state file), and prints "no sessions" with exit 0 when there are none (FR7, FR8)

**Given** a running session `claude-<workspace>`
**When** I run `scripts/stop.sh <workspace>`
**Then** it runs `tmux kill-session -t claude-<workspace>` for that one session only and exits 0
**And** other `claude-*` sessions on the host are untouched; the script never uses a wildcard or `kill-server` (AD-4)

**Given** no session named `claude-<workspace>`
**When** I run `stop.sh <workspace>`
**Then** it exits 2 with one line on stderr

**Given** `NODE_ROLE=client`
**When** I run `status.sh` or `stop.sh`
**Then** each exits 2 with one line on stderr (AD-1)

**Given** both scripts
**Then** output contains no tokens, node names or tailnet IPs, each exposes `--check`, and each conforms to AD-8

### Story 2.3: Connect from a client to a host workspace with one command

As a user on a client node,
I want `connect.sh <node> <workspace>` to drop me into Claude Code on that host,
So that reaching any host is one command, and re-running it after a drop reattaches.

**Acceptance Criteria:**

**Given** `NODE_ROLE=client|both` on the client and an enrolled host `<node>`
**When** I run `scripts/connect.sh <node> <workspace>`
**Then** it runs `tailscale ssh -t <user>@<node> -- "$HOME/agentic-workstation/scripts/start-claude.sh" <workspace>` (absolute repo path, since the non-interactive shell does not source the login profile) and I land in Claude Code inside the workspace (FR4)
**And** `<user>` comes from `SSH_USER` in `config/local.env`, defaulting to the current login user

**Given** the session `claude-<workspace>` already exists on the host
**When** I run the same `connect.sh` command again
**Then** I am reattached to it with scrollback intact (FR7)

**Given** I run `connect.sh` with no arguments
**When** it executes
**Then** it lists the currently online tailnet peers parsed from `tailscale status` text output (no `jq`) and exits 0; it keeps no list of hosts in any file (FR10, AD-2)

**Given** `SSH_USER=root`, a missing `<workspace>` argument, or `NODE_ROLE=host`
**When** I run `connect.sh`
**Then** it exits 2 with one line on stderr (AD-1, AD-6)

**Given** `config/ssh_config.example`
**Then** it ships a `Host <node>` entry with `ServerAliveInterval 15` and `ServerAliveCountMax 3`, documented as optional for plain `ssh` users (NFR2)
**And** `connect.sh` exposes `--check` and conforms to AD-8

### Story 2.4: Survive a dropped link and resume within a minute, in both directions

As the owner,
I want a documented, verified reconnect and recovery flow,
So that a network drop or laptop lid never costs me a Claude Code session.

**Acceptance Criteria:**

**Given** a session started with `connect.sh` from node A to node B
**When** the link is killed (network off, terminal closed, laptop lid) and I re-run `connect.sh <node> <workspace>` after the network is back
**Then** I am back in the same Claude Code session with prior scrollback and conversation context in under 60 seconds (NFR2, FR6)

**Given** the same setup from B to A while the A→B session is still running
**When** I start `claude-<workspace>` on A from B
**Then** both sessions coexist (one per host tmux server) and neither is affected by the other (FR8, M1)

**Given** `config/tmux.conf.example`
**Then** it sets a large `history-limit` and mouse support, and the docs explain how to install it as `~/.tmux.conf` (optional)

**Given** `docs/sessions.md`
**Then** it documents: the reattach flow, the tmux detach key, recovery after a host reboot (`start-claude.sh` then `claude --resume claude-<workspace>` inside the new session — documented, not scripted), the `tailscaled`-restart gap and its `tailscale serve --tcp 2222 22` shim, and that transcripts live in `~/.claude/` on the host (AD-4, AD-7)

**Given** the M1 protocol (A→B start, kill link, reconnect, intact; then B→A)
**When** it is executed on two real nodes
**Then** the outcome (pass, measured reconnect time) is recorded in the story notes without node names

## Epic 3: Host over OpenSSH when Tailscale SSH isn't an option

A host that must keep the Tailscale GUI app (or otherwise can't serve Tailscale SSH) opts into hardened key-only OpenSSH over the tailnet; a client enrolls its own ed25519 key and connects with `connect.sh --fallback`, with `doctor.sh` verifying key hygiene.

### Story 3.1: Opt a host into hardened key-only OpenSSH over the tailnet

As the owner of a host that cannot run the Tailscale SSH server,
I want a documented, verified way to expose OpenSSH only over the tailnet with keys only,
So that the host is still reachable without weakening the security baseline.

**Acceptance Criteria:**

**Given** `docs/fallback-openssh.md`
**When** I follow it on macOS (Remote Login) or Linux/WSL (`openssh-server`)
**Then** sshd runs with `PasswordAuthentication no`, `PermitRootLogin no`, `KbdInteractiveAuthentication no`, `AllowUsers <user>`, verified with `sshd -T`, and the guide states reachability is limited by the tailnet (no public port-forward), not by pinning `ListenAddress` (AD-3, FR18)

**Given** `config/local.env` with `FALLBACK_SSHD=1`
**When** I run `doctor.sh` on that host
**Then** the "Tailscale SSH advertised" check is SKIP and new checks verify sshd is running, the four hardening settings are effective, and `~/.ssh` / `~/.ssh/authorized_keys` are 0700 / 0600 (FR15)
**And** with `FALLBACK_SSHD=0` (default) those fallback checks are SKIP

**Given** the guide
**Then** it is labelled the documented exception, uses placeholders only, commits no key material, and the host still joins the tailnet normally (`tailscale up` without `--ssh`)

### Story 3.2: Enroll a client key on a fallback host and connect with `--fallback`

As a user on a client node,
I want to register my machine's own ed25519 key on a fallback host and connect with the same `connect.sh` verb,
So that the exception path stays one command and one key per machine.

**Acceptance Criteria:**

**Given** `NODE_ROLE=host|both` and `FALLBACK_SSHD=1` on the host
**When** I run `scripts/enroll.sh <pubkey-file>` (or pipe the key on stdin)
**Then** it validates the input is a single ed25519 public key, appends it to `~/.ssh/authorized_keys` only if not already present, enforces 0700/0600 on `~/.ssh` and `authorized_keys`, and never prints the key (FR18, FR15)

**Given** `FALLBACK_SSHD` is not `1`, the input is not an ed25519 public key, or `NODE_ROLE=client`
**When** I run `enroll.sh`
**Then** it exits 2 with one line on stderr

**Given** the client guide section in `docs/fallback-openssh.md`
**Then** it instructs to generate one ed25519 key per client machine with a passphrase and ssh-agent, never copy a private key between machines, deliver the public key to the host out-of-band (e.g. `tailscale file cp`), and add a `Host <node>` entry to the client's untracked `~/.ssh/config` based on `config/ssh_config.example`

**Given** a client whose `~/.ssh/config` has an entry for `<node>`
**When** I run `scripts/connect.sh --fallback <node> <workspace>`
**Then** it runs `ssh -t <node> -- "$HOME/agentic-workstation/scripts/start-claude.sh" <workspace>` and I land in (or reattach to) Claude Code on the host
**And** `connect.sh` never probes for fallback hosts nor keeps a list of them; without `--fallback` behaviour is unchanged (AD-3)

**Given** both scripts
**Then** `enroll.sh` exposes `--check`, both conform to AD-8, and `doctor.sh` aggregates `enroll.sh --check` on hosts where it applies
