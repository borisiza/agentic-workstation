# Epic 3 Context: Host over OpenSSH when Tailscale SSH isn't an option

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Some hosts can't or won't run the Tailscale SSH server (e.g. a Mac that keeps the GUI app instead of the open-source `tailscaled` variant). This epic gives those hosts a documented, opt-in fallback: hardened, key-only OpenSSH reachable only over the tailnet, with a matching client enrollment flow so a client's own ed25519 key gets installed and `connect.sh --fallback` still gets the user into Claude Code in one command. It matters because without it, a subset of otherwise-valid hosts would be unreachable, breaking the "any node to any node" MVP goal — while still holding the line that this is an explicit exception, never a second first-class auth system or a path to weaker security.

## Stories

- Story 3.1: Opt a host into hardened key-only OpenSSH over the tailnet
- Story 3.2: Enroll a client key on a fallback host and connect with `--fallback`

## Requirements & Constraints

- The fallback is strictly opt-in per host, toggled by `FALLBACK_SSHD` in the host's gitignored `config/local.env` (`0` default/off, `1` enabled); it never replaces or auto-detects in place of Tailscale SSH.
- sshd hardening baseline is fixed: `PasswordAuthentication no`, `PermitRootLogin no`, `KbdInteractiveAuthentication no`, `AllowUsers <user>`, verified with `sshd -T`. No password auth, no root login, ever.
- Reachability comes from the tailnet boundary alone (no public port-forward) — not from pinning `ListenAddress` to a tailnet IP.
- Auth is ed25519 keys only, one key per client machine, never copied between machines; private keys never leave the machine that generated them.
- `~/.ssh` and `~/.ssh/authorized_keys` must carry 0700 / 0600 permissions, checked both by the setup guide and by `doctor.sh`.
- `doctor.sh` must gain new checks for the fallback path: sshd running, the four hardening settings effective, and key-permission hygiene — all SKIP when `FALLBACK_SSHD=0` (the default), and the existing "Tailscale SSH advertised" check SKIPs when `FALLBACK_SSHD=1`.
- `enroll.sh` validates that its input is exactly one ed25519 public key, appends it to `authorized_keys` only if not already present, enforces the same 0700/0600 permissions, and never prints the key. It refuses (exit 2, one-line stderr) when `FALLBACK_SSHD` isn't `1`, the input isn't an ed25519 pubkey, or the node's role is `client`.
- `connect.sh --fallback <node> <workspace>` runs `ssh -t <node> -- "$HOME/agentic-workstation/scripts/start-claude.sh" <workspace>`, relying on the client's own untracked `~/.ssh/config` entry for `<node>` (based on `config/ssh_config.example`). Without `--fallback`, `connect.sh` behavior is unchanged — it never probes for or keeps a list of fallback hosts.
- Docs, keys, and any host-identifying values must follow public-repo hygiene: placeholders only (`<node>`, `<user>`), no committed key material, no real hostnames/IPs.
- A fallback host still joins the tailnet normally (`tailscale up` without `--ssh`).
- `enroll.sh` exposes `--check` (self-test, no side effects); `doctor.sh` aggregates it on hosts where the fallback applies.

## Technical Decisions

- **AD-3 (Tailscale SSH primary, OpenSSH is a per-host exception):** the repo commits no ACL policy file and no auth keys under the primary path; OpenSSH-over-tailnet exists solely to cover hosts that can't serve Tailscale SSH, gated by `FALLBACK_SSHD=1`. This was chosen specifically to avoid a key mesh — distributing N public keys to N hosts scales as N×(N−1) edits at 5+ nodes, which the "onboarding touches only that node" invariant (AD-1, NFR6) forbids as the primary mechanism. The fallback is deliberately the exception, not a peer of Tailscale SSH.
- **Layering (L2 transport):** OpenSSH-over-tailnet lives at the same L2 transport layer as Tailscale SSH but with a different trust model — host key trust is TOFU/`known_hosts` per client instead of coordination-server-verified identity.
- **Script conventions (AD-8):** `enroll.sh` is bash-3.2-compatible (`#!/usr/bin/env bash`, `set -euo pipefail`, no associative arrays), passes shellcheck, has no `jq`/Python dependency, and exposes `--check`. Runtime dependency added by this epic: `ssh`/`sshd`, only on hosts with `FALLBACK_SSHD=1`.
- **Config surface:** `config/local.env` gains `FALLBACK_SSHD` (`0`/`1`) alongside existing `NODE_ROLE`, `WORKSPACES_DIR`, `SSH_USER`; the committed twin is `config/local.env.example`. Client-side fallback config lives in the client's own untracked `~/.ssh/config`, seeded from committed `config/ssh_config.example`.
- **Source tree additions relevant to this epic:** `scripts/enroll.sh`, `docs/fallback-openssh.md`, `config/ssh_config.example`.
- **Error/logging conventions apply:** non-zero exit + single-line stderr message on failure, stdout-only logging, never printing secrets, keys, or peer names.
- **Public-repo hygiene (AD-7):** `.gitignore` must cover `authorized_keys` and any key files (`*.key`, `*.pem`); `gitleaks` pre-commit/CI gates apply to anything touched in this epic same as elsewhere.

## Cross-Story Dependencies

- Story 3.2 depends on Story 3.1: the host must already have hardened sshd running and `FALLBACK_SSHD=1` set before a client key can be usefully enrolled or `connect.sh --fallback` attempted.
- Both stories depend on `doctor.sh` and `connect.sh`/`start-claude.sh` already existing from earlier epics (Epic 1 enrollment, Epic 2 session lifecycle) — this epic extends those scripts rather than introducing a new lifecycle.
- `doctor.sh`'s aggregation of `enroll.sh --check` (Story 3.2) depends on `enroll.sh` implementing `--check` per the AD-8 convention used by all other scripts.
