---
title: Agentic Workstation PRD
status: final
created: 2026-09-10
updated: 2026-09-10
---

# Agentic Workstation — PRD

## Overview

Agentic Workstation turns a personal machine (initially a Mac) into a remotely reachable agentic development station. The MVP objective: **connect over SSH from one PC to another PC and run Claude Code there**, with persistent sessions that survive disconnects.

Host = the Mac this repo lives on; client = another PC running macOS, native Windows, or Windows WSL. The two machines are always on different networks, so connectivity runs over a **Tailscale tailnet** from day one. Single user for the MVP.

The repository is **public**. Everything committed — code, scripts, docs, BMAD artifacts — must be safe to publish: no secrets, no tokens, no personal IPs/hostnames, no machine inventory that leaks private detail.

## Goals

- G1. From a second PC, open a terminal on the workstation via SSH using key-based auth only.
- G2. Run Claude Code on the workstation from that remote terminal, working on a real repository.
- G3. Disconnect (network drop, laptop closed) and reattach later to the **same** Claude Code session with its context intact.
- G4. Keep the public repository publishable at all times (zero committed secrets).

**Done for MVP:** G1–G4 all demonstrated end to end.

## Non-goals (MVP)

- Control from a phone / Claude mobile Remote Control (roadmap — see poc-plan Phase 3).
- Codex remote control (roadmap).
- Web portal, Firebase auth, multi-user, multi-tenancy (roadmap Phase 9).
- Oracle Cloud migration (roadmap Phase 10).
- Exposing SSH to the public internet — connectivity is always over the tailnet, never a router port-forward.

## Users

- **Primary:** the product owner, a solo developer operating both machines (clients: macOS, Windows, Windows WSL).
- **Secondary:** anyone cloning the public repo to replicate the setup on their own hardware. Docs and scripts must therefore be generic — parameterized, no personal values baked in.

## Functional Requirements

### F1. SSH access to the workstation
- FR1. The workstation accepts SSH connections authenticated **exclusively by key** (ed25519); password and root login disabled.
- FR2. A documented, repeatable setup procedure (script or guide) enables SSH on the host and installs the client's public key without ever committing key material.
- FR3. Connectivity runs over a Tailscale tailnet; no ports exposed to the public internet (sshd reachable only via the tailscale interface).
- FR15. Key material and local session-state files carry restrictive permissions (0600 files / 0700 dirs), verified by `doctor.sh`.

### F2. Run Claude Code remotely
- FR4. From the SSH session, the user can launch Claude Code in a chosen workspace directory with one command (e.g. `scripts/start-claude.sh <workspace>`).
- FR5. Claude Code runs with the project's normal permission mode — no `--dangerously-skip-permissions` bypass. Approvals happen in the remote terminal.
- FR16. A session operates only inside its workspace directory (allowlist); it must not touch sibling workspaces.

### F3. Persistent sessions
- FR6. Claude Code runs inside a persistent multiplexer session so a dropped SSH connection does not kill it. [ASSUMPTION] tmux, pending the architecture-phase evaluation of Claude Code's native daemon/`--resume` persistence (OQ5).
- FR7. Reattaching (`scripts/status.sh` to list, then attach) restores the running session with scrollback.
- FR8. Sessions carry a human-readable name derived from their workspace; metadata recorded locally (id, name, workspace, status, startedAt) contains **no sensitive values** and is gitignored if it lives inside the repo tree.

### F4. Operability scripts
- FR9. `scripts/doctor.sh` verifies prerequisites (ssh, tmux, claude, git) and reports gaps without printing secrets.
- FR10. `scripts/start-claude.sh`, `status.sh`, `stop.sh` cover the session lifecycle (poc-plan Phase 5, reduced to Claude-only for MVP).

### F5. Public-repo hygiene
- FR11. `.gitignore` excludes keys, tokens, session state, logs, and any machine-inventory output (e.g. `docs/discovery/`).
- FR12. A pre-commit secret scan (e.g. gitleaks) blocks accidental secret commits.
- FR13. Docs use placeholders (`<host>`, `<user>`) — real hostnames, IPs, usernames and Tailscale node names never appear in committed files.
- FR14. Client setup docs cover all three supported clients: macOS, native Windows (built-in OpenSSH), and Windows WSL.

## Non-Functional Requirements

- NFR1. **Security is the hard constraint:** key-only SSH, no public port exposure, no privileged execution, logs free of tokens.
- NFR2. Reconnection after a network drop takes under a minute and loses no session state; a reconnect that exceeds this or loses state is a defect, not an accepted limitation.
- NFR3. Setup is reproducible by a stranger from the README alone: clean Mac host plus any of the three supported clients.
- NFR4. Everything in the repo works with placeholder config; personal values live only in untracked local files (e.g. `config/local.env`, gitignored) or the macOS Keychain.
- NFR5. The Git remote (GitHub) is the backup — work lands on pushed branches; third-party tools/scripts are reviewed before adoption.

## Success Metrics

- M1. Full demo: client PC → SSH → start Claude Code → kill the connection → reconnect → session intact.
- M2. `gitleaks` (or equivalent) reports zero findings on the repo history at MVP close.
- M3. A second machine can be onboarded following only committed docs, in under 30 minutes.

**Counter-metric:** convenience must not erode security — no metric improvement justifies password auth, port-forwarding, or permission bypasses.

## Roadmap (post-MVP, from poc-plan)

1. Claude Remote Control from phone (poc-plan Phase 3) — confirmed roadmap; revisit priority once the SSH flow is a daily driver.
2. Codex remote sessions (Phase 4).
3. Workspace isolation model (Phase 7).
4. Firebase-authenticated local portal (Phase 9).
5. Oracle Cloud A1 migration + Tailscale (Phase 10).

## Open Questions

Deferred to the architecture phase (owner: architecture doc; revisit before epics):

- OQ4. Is mosh worth adding on top of SSH for flaky links, or does tmux reattach alone cover NFR2?
- OQ5. tmux vs Claude Code's native daemon/`--resume` for persistence (FR6 assumes tmux until evaluated).