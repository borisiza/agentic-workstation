---
title: Agentic Workstation PRD
status: final
created: 2026-09-10
updated: 2026-09-10
---

# Agentic Workstation — PRD

## Overview

Agentic Workstation turns the owner's personal machines into a mesh of remotely reachable agentic development stations. The MVP objective: **connect over SSH from any PC to any other PC and run Claude Code there**, with persistent sessions that survive disconnects.

**Symmetric node model:** every machine installs the same repo and declares a role — `host`, `client`, or `both`. There is no hub; A→B and B→A are two independent connections. The mesh starts at **five or more nodes**. Hosts are macOS, Linux, or **Windows via WSL2** (the WSL distro joins the tailnet as its own Linux node); clients are macOS, native Windows, or WSL. Nodes are always on different networks, so connectivity runs over a **Tailscale tailnet** from day one and authentication is **Tailscale SSH** (identity = the owner's Tailscale account, no key distribution). Single user for the MVP.

The repository is **public**. Everything committed — code, scripts, docs, BMAD artifacts — must be safe to publish: no secrets, no tokens, no personal IPs/hostnames, no machine inventory that leaks private detail.

## Goals

- G1. From any node, open a terminal on any host node via SSH over the tailnet, authenticated by Tailscale identity — no passwords, no shared keys.
- G2. Run Claude Code on the host from that remote terminal, working on a real repository.
- G3. Disconnect (network drop, laptop closed) and reattach later to the **same** Claude Code session with its context intact.
- G4. Keep the public repository publishable at all times (zero committed secrets, zero committed machine names).
- G5. Adding a node touches only that node — no other machine is reconfigured.

**Done for MVP:** G1–G5 all demonstrated end to end, in both directions between at least two nodes.

## Non-goals (MVP)

- Control from a phone / Claude mobile Remote Control (roadmap — see poc-plan Phase 3).
- Codex remote control (roadmap).
- Web portal, Firebase auth, multi-user, multi-tenancy (roadmap Phase 9).
- Oracle Cloud migration (roadmap Phase 10).
- Exposing SSH to the public internet — connectivity is always over the tailnet, never a router port-forward.
- A central hub, host registry, or control plane — discovery is `tailscale status`; the roadmap portal (Phase 9) is the first place any registry may appear.
- Native Windows as a **host** — Tailscale SSH has no Windows server; a Windows PC hosts through its WSL2 node.

## Users

- **Primary:** the product owner, a solo developer operating a mesh of five or more machines (hosts: macOS, Linux, Windows via WSL2; clients: macOS, native Windows, WSL).
- **Secondary:** anyone cloning the public repo to replicate the setup on their own hardware. Docs and scripts must therefore be generic — parameterized, no personal values baked in.

## Functional Requirements

### F1. SSH access between nodes
- FR1. Host nodes accept SSH connections authenticated **exclusively by Tailscale SSH** (tailnet identity, ACL `check` mode re-auth); no password, no root login, no sshd of their own on the primary path.
- FR2. A documented, repeatable per-node setup (script or guide) joins the node to the tailnet and, for hosts, advertises Tailscale SSH (`tailscale up --ssh`) — without ever committing tokens, auth keys, or key material.
- FR3. Connectivity runs over the Tailscale tailnet only; no ports exposed to the public internet.
- FR15. Key material and local session-state files carry restrictive permissions (0600 files / 0700 dirs), verified by `doctor.sh`.
- FR17. Each node declares its role (`host`, `client`, `both`) in a gitignored local config (e.g. `config/local.env`); scripts read the role from there, never from committed files.
- FR18. **Fallback path:** a host that cannot run the Tailscale SSH server (e.g. a Mac keeping the GUI app, see OQ7) exposes OpenSSH bound to the tailscale interface, key-only (ed25519, one key per client machine, never copied between machines), password and root login disabled; `scripts/enroll.sh` installs a client's public key on that host. This path is opt-in per host and documented as the exception.

### F2. Run Claude Code remotely
- FR4. From any client node, the user reaches a host and lands in Claude Code inside a chosen workspace with one command (`scripts/connect.sh <node> <workspace>`); on the host itself the equivalent is `scripts/start-claude.sh <workspace>`.
- FR5. Claude Code runs with the project's normal permission mode — no `--dangerously-skip-permissions` bypass. Approvals happen in the remote terminal.
- FR16. A session operates only inside its workspace directory (allowlist); it must not touch sibling workspaces.

### F3. Persistent sessions
- FR6. Claude Code runs inside a persistent multiplexer session so a dropped SSH connection does not kill it. [ASSUMPTION] tmux, pending the architecture-phase evaluation of Claude Code's native daemon/`--resume` persistence (OQ5).
- FR7. Reattaching (`scripts/status.sh` to list, then attach) restores the running session with scrollback.
- FR8. Sessions are namespaced **per host** and named `claude-<workspace>`; simultaneous A→B and B→A sessions never collide. Metadata recorded locally (id, name, workspace, status, startedAt) contains **no sensitive values** and is gitignored if it lives inside the repo tree.

### F4. Operability scripts
- FR9. `scripts/doctor.sh` verifies prerequisites (tailscale + tailnet membership, `--ssh` advertised on hosts, tmux, claude, git) and reports gaps without printing secrets or node names.
- FR10. `scripts/start-claude.sh`, `status.sh`, `stop.sh` cover the session lifecycle on a host (poc-plan Phase 5, reduced to Claude-only for MVP); `scripts/connect.sh` is the client side (lists reachable hosts from `tailscale status --json`, then attaches); `scripts/enroll.sh` exists only for the FR18 fallback.

### F5. Public-repo hygiene
- FR11. `.gitignore` excludes keys, tokens, session state, logs, node role config, and any machine-inventory output (e.g. `docs/discovery/`).
- FR12. A pre-commit secret scan (e.g. gitleaks) blocks accidental secret commits.
- FR13. Docs use placeholders (`<node>`, `<user>`) — real hostnames, IPs, usernames and Tailscale node names never appear in committed files; there is **no host list in the repo**, discovery is `tailscale status`.
- FR14. Setup docs cover every supported node type: hosts on macOS (open-source `tailscaled`), Linux, and Windows via WSL2 (WSL distro as its own tailnet node, see OQ6); clients on macOS, native Windows, and WSL.

## Non-Functional Requirements

- NFR1. **Security is the hard constraint:** identity- or key-only SSH, no public port exposure, no privileged execution, logs free of tokens.
- NFR2. Reconnection after a network drop takes under a minute and loses no session state; a reconnect that exceeds this or loses state is a defect, not an accepted limitation (mosh as a mitigation: OQ4).
- NFR3. Setup is reproducible by a stranger from the README alone, on any supported host type (macOS, Linux, Windows/WSL2) plus any supported client.
- NFR4. Everything in the repo works with placeholder config; personal values live only in untracked local files (e.g. `config/local.env`, gitignored) or the macOS Keychain.
- NFR5. The Git remote (GitHub) is the backup — work lands on pushed branches; third-party tools/scripts are reviewed before adoption.
- NFR6. The mesh scales by addition only: onboarding node N+1 changes nothing on nodes 1..N (no key redistribution, no config edits, no registry update).

## Success Metrics

- M1. Full demo, both directions: node A → node B, start Claude Code, kill the connection, reconnect, session intact — then the same from B → A.
- M2. `gitleaks` (or equivalent) reports zero findings on the repo history at MVP close.
- M3. A new node (any supported host type) can be onboarded following only committed docs, in under 30 minutes, without touching any other node.

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
- OQ6. WSL2 as a tailnet node: how `tailscaled` auto-starts inside WSL (systemd in WSL) and how WSL itself is kept booted after a Windows restart, so the host is reachable unattended. [ASSUMPTION] solvable with WSL systemd support; unverified.
- OQ7. macOS hosts need the open-source `tailscaled` variant (CLI-only, no GUI app) to serve Tailscale SSH. [ASSUMPTION] installable via Homebrew formula + `brew services`; unverified. Is losing the GUI acceptable on every Mac host, or does some Mac stay on the FR18 OpenSSH fallback?