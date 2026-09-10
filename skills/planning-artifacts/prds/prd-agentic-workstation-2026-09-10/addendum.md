# Addendum — Agentic Workstation PRD

Depth that belongs downstream (architecture / ADRs), not in the PRD.

## Transport decision (feeds ADR)

- **LAN SSH**: zero extra moving parts; rejected — the PCs are never co-located.
- **Tailscale tailnet (network layer)**: no public ports, identity-based, works across networks; adds a third-party dependency. **Chosen** (owner confirmed: machines always on different networks).
- **Router port-forward + public sshd**: rejected — public repo + public port is an unnecessary attack surface for a solo tool.
- **mosh**: candidate on top of SSH for flaky links; evaluate in architecture, not required for MVP (tmux already covers persistence).

### Multi-node model (owner decisions 2026-09-10: Windows hosts via WSL; 5+ nodes)

Symmetric nodes, no hub. Bidirectional = two independent one-way connections; each host runs its own tmux server, so `claude-<workspace>` on A and on B never collide.

| | Tailscale SSH (primary, FR1) | OpenSSH over tailnet (fallback, FR18) |
|---|---|---|
| Auth | tailnet identity, ACL `check` mode re-auth | ed25519 key per client machine |
| Server platforms | Linux; macOS **open-source `tailscaled` only** (Standalone / App Store apps lack it); **Windows: client only** | anything with sshd (mac Remote Login, Linux, WSL) |
| Host key trust | verified via the coordination server (`tailscale ssh`) | TOFU / `known_hosts` per client |
| Onboarding node N+1 | install + `tailscale up --ssh`; nobody else changes | N `authorized_keys` edits → at 5+ nodes, 20+ pairs; rejected as the primary |
| Port | fixed 22 | free |
| Known limits | restarting `tailscaled` drops sessions (tmux survives); `tailscale serve --tcp 2222 22` as backup | key hygiene is manual (`enroll.sh`) |

Sources: Context7 `/websites/tailscale` (Tailscale SSH prerequisites, macOS variants, CLI `ssh`, default ACL `autogroup:member → autogroup:self` in `check` mode).

**Windows as host = WSL2 as its own tailnet node.** Claude Code and tmux already live in WSL; running `tailscaled` *inside* the distro gives it a MagicDNS name and a Tailscale SSH server, which removes the WSL2 NAT problem entirely (no `netsh portproxy`, no `.wslconfig networkingMode=mirrored`). Tailscale on the Windows side is optional and only matters if native Windows also acts as a client. Open point: keeping WSL and `tailscaled` up unattended after a Windows reboot (OQ6).

**Why the key mesh was dropped at 5+.** One key per client machine is still right (Vex: a shared private key means one compromise owns the mesh), but distributing N public keys to N hosts scales as N×(N−1) and every join/leave touches every node — exactly what NFR6 forbids. Identity-based SSH makes the join a local-only operation.

## Session persistence

- tmux chosen over screen (ubiquitous, scriptable) and over relying on any Claude Code daemon mode — evaluate native daemon/`--resume` behavior during architecture (poc-plan Phase 6 asks the same question).
- launchd services deferred to Phase 6; MVP scope is "survives disconnect", not "survives reboot".

## poc-plan mapping

| poc-plan phase | MVP status |
|---|---|
| 0 discovery, 1 repo | done/absorbed |
| 3 Claude Remote Control (phone) | deferred — MVP replaces channel with SSH |
| 4 Codex | deferred |
| 5 session scripts | in MVP (Claude-only subset; `doctor.sh` checks reduced from Homebrew/Node/Docker/tmux to ssh/tmux/claude/git — deliberate MVP cut) |
| 6 24/7 persistence | partial (tmux only) |
| 7 workspaces, 8 security | 8's controls absorbed as FR11–13/NFR1; 7 deferred |
| 9 Firebase portal, 10 Oracle | roadmap |

## Public-repo hygiene notes

- gitleaks as pre-commit + CI candidate; alternative: git-secrets.
- `docs/discovery/` output (machine inventory) must stay untracked — it leaks hardware/user detail even without credentials.

## Research digest (2026 landscape — feeds ADRs)

- Winning pattern in the wild: **Tailscale (network) + SSH/mosh (transport) + tmux (persistence)**, with a mobile UX layer (Claude Remote Control `/rc`, or Happy — happy.engineering, OSS, E2E-encrypted, also drives Codex) optional on top. Layers are independent: if the app dies, `ssh` + `tmux attach` always remains.
- sshd hardening baseline (FR18 fallback hosts only): `PasswordAuthentication no`, `PermitRootLogin no`, `KbdInteractiveAuthentication no`, `AllowUsers <user>`; bind sshd to the tailscale interface (zero public ports). Primary path is Tailscale SSH (identity ACLs + check-mode re-auth), which needs no sshd.
- Keys (fallback only): one ed25519 key **per client device**, passphrase + ssh-agent; never share a private key across PCs.
- Never commit: `id_*`, `~/.ssh/config` with internal hosts/IPs, `authorized_keys`, `ANTHROPIC_API_KEY`, anything under `~/.claude/` / `~/.codex/`, `.env`, Tailscale tokens. Agent credentials live in the remote home, outside the repo tree.
- Auto-approve agents on a public repo can `git add` sensitive files — defensive `.gitignore` + diff review before push; consider a dedicated non-sudo user for unattended runs (prompt-injection blast radius).
- Alternatives surveyed and parked: VS Code Remote-SSH (heavy, IDE use-case), claude.ai/code web + `--teleport` (not your hardware), Happy (roadmap candidate for the phone phase).
