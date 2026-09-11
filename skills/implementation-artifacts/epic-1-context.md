# Epic 1 Context: Enroll a machine as a mesh node

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic makes any of the owner's machines (Linux, macOS, Windows/WSL2, or a client-only PC) a working node in the mesh: clone the public repo, declare a local role, join the Tailscale tailnet with Tailscale SSH advertised (or the documented OpenSSH fallback, delivered in Epic 3), pass `doctor.sh`, and be reachable by `tailscale ssh` — while the repo itself stays safe to publish at every commit. It lays the foundation (repo skeleton, hygiene gates, role config, readiness check, per-platform onboarding docs) that Epic 2 (running Claude Code sessions) builds on.

## Stories

- Story 1.1: Publishable repo skeleton with hygiene gates
- Story 1.2: Declare the node role and verify readiness with doctor.sh
- Story 1.3: Enroll a Linux host
- Story 1.4: Enroll a macOS host
- Story 1.5: Enroll a Windows host via WSL2
- Story 1.6: Set up a client-only node and the onboarding README

## Requirements & Constraints

- The repo tree must exist from the first commit: `scripts/`, `config/`, `docs/`, `.github/workflows/hygiene.yml`, `.gitleaks.toml`, `.pre-commit-config.yaml`, `.gitignore`, `README.md` (empty dirs held by `.gitkeep`).
- `.gitignore` must exclude local role config, key material (`*.key`, `*.pem`, `authorized_keys`), session/log output, and any machine-inventory output (e.g. a discovery directory) — none of these may ever appear as trackable.
- A pre-commit secret scan must block a staged fake secret while allowing docs containing only placeholder tokens (`<node>`, `<user>`, `<workspace>`, `<distro>`); the same scan must run in CI on every push/PR and fail the job on any finding, alongside a shell linter over all scripts.
- Zero secrets/host names anywhere in committed history is a hard success bar; no ACL policy file, auth key, or host list is ever committed. Discovery of peers happens only at runtime via the tailnet's own status output.
- Each node declares its role (host/client/both) only in a local, gitignored config file; a single readiness command reads that role (and nothing else) and reports pass/fail per prerequisite (tailnet tooling, tailnet membership, session multiplexer, agent CLI, vcs) with actionable, one-line failure messages — never printing secrets, tokens, tailnet IPs, or node names. Missing/invalid role must fail loudly and immediately.
- Host-role readiness additionally verifies: SSH-over-tailnet is advertised, the configured workspaces directory exists, and the platform-specific backend contract (see Technical Decisions) is satisfied. Key material and any local session-state files must carry restrictive permissions (private dirs not group/world-readable, private key files owner-only), and this must be checked, not just assumed.
- Every script must expose a side-effect-free self-test mode that the readiness command aggregates across all present scripts.
- Onboarding docs must exist for every supported node type (Linux host, macOS host, WSL2 host, and a generic client covering macOS/Windows/WSL) and must be reproducible by a stranger from the README alone, using placeholders only — no real hostnames, IPs, usernames, or tailnet node names anywhere in committed docs.
- Onboarding a new node must not require touching or reconfiguring any other node already in the mesh.
- A full node onboarding, following only the committed docs, must complete in well under the target ceiling (30 minutes) without modifying any other node — this needs to be demonstrated and recorded, not just asserted.

## Technical Decisions

- Symmetric peer mesh, no hub/registry: every node clones the same repo to a fixed path (`$HOME/agentic-workstation`); role lives only in a gitignored `config/local.env` (`NODE_ROLE=host|client|both`, plus `WORKSPACES_DIR`, `FALLBACK_SSHD`, `SSH_USER`), read via precedence env file → environment → flags. A committed `config/local.env.example` twin documents the shape. No script may branch on machine identity or list nodes.
- Peers are addressed only by MagicDNS node name; raw tailnet IPs must never appear in scripts or docs, and nothing may listen on or forward a non-tailnet interface.
- Tailscale SSH (`tailscale up --ssh`) is the primary transport, authenticated purely by tailnet identity under the tailnet's default check-mode ACL rule — no ACL policy file is committed. The OpenSSH fallback (opt-in per host) belongs to Epic 3, but its existence is referenced in the macOS doc.
- Platform contract for hosts: Linux runs the tailnet daemon as a system service; macOS must run the open-source daemon via the Homebrew formula/`brew services` (not the GUI app) to serve SSH; Windows hosts only via a WSL2 distro configured as its own tailnet node, requiring `systemd=true` in WSL boot config so the daemon runs under systemd, plus Windows-side keep-alive settings (idle timeouts disabled, a logon task keeping the distro alive, no-sleep power settings) — these Windows-side items are documented, not scripted (outside repo). The readiness check must encode this contract as explicit checks.
- Hygiene is enforced, not promised: gitleaks runs both pre-commit and as a CI action across full history; a `.gitleaks.toml` allowlist covers placeholder tokens; scripts never echo tokens/keys/peer names to any log; agent transcripts stay in the user's own Claude Code data directory, never inside the repo or a workspace.
- Every script: `#!/usr/bin/env bash` + `set -euo pipefail`, bash 3.2-compatible (no associative arrays, no case-conversion parameter expansion), shellcheck-clean, no `jq`/Python — parses tailnet status as plain text. Runtime deps are limited to the tailnet client, session multiplexer, agent CLI, and vcs (plus ssh/sshd only for Epic 3 hosts). Scripts don't depend on each other (this epic has no cross-script calls yet — that starts in Epic 2).
- Stack pins relevant to this epic: Tailscale 1.102.3, gitleaks 8.30.1, shellcheck 0.11.0, WSL ≥ 2.4.4 (verify with the platform's own version command), tmux/claude/git present but otherwise version-unpinned here.
- CI has exactly one job class relevant here (shellcheck + gitleaks); there is no tailnet in CI and no staging environment — one real environment, the owner's tailnet.

## Cross-Story Dependencies

- Story 1.1 (skeleton + hygiene gates) must land before any other story — it creates the directories and gate config every later story writes into.
- Story 1.2 (`doctor.sh` + role config) must exist before Stories 1.3–1.5, since each platform enrollment story ends with `doctor.sh` reporting all-pass for that platform, including platform-specific checks doctor.sh must already support.
- Stories 1.3, 1.4, 1.5 (Linux/macOS/WSL host docs) are independent of each other but all feed Story 1.6, whose README routes to each of them plus the client doc.
- Story 1.6's client doc and README are the last piece needed to demonstrate the under-30-minute onboarding metric end to end.
- This epic is a prerequisite for Epic 2 (running/resuming Claude Code sessions), which assumes role config and tailnet membership already work.
