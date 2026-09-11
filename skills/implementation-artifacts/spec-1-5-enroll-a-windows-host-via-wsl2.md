---
token_cost: {input: 139819, output: 48128, cache_read: 5012783, total: 5200730}
final_revision: '91070ed403673ebcecad1b19e25322f4233ae9c3'
title: 'Enroll a Windows host via WSL2'
type: 'feature'
created: '2026-09-11'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '1f9d8657214a44d0c3fad09baa1cda9c3703f543'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Windows has no native path to join the mesh as a Tailscale SSH host — the Windows Tailscale app has no SSH server, so a WSL2 distro must become its own tailnet node, and WSL2 distros idle-suspend by default, so unattended reachability needs Windows-side settings outside this repo's scripts.

**Approach:** Add `docs/node-wsl.md`, mirroring `docs/node-linux.md`'s structure: pick one distro → enable `systemd` in `/etc/wsl.conf` → `wsl --shutdown` and confirm `systemd` is PID 1 → install Tailscale inside the distro → `tailscale up --ssh` → tool install → repo clone → role config → `doctor.sh` all-clear (including the WSL `platform-contract` PASS) → an added "unattended reachability" section for the Windows-side `.wslconfig`/Task Scheduler/power settings → the same cross-node verification, tailnet-ACL, and recovery-caveat sections as the Linux/macOS guides.

## Boundaries & Constraints

**Always:** Guide states the `wsl --version` >= 2.4.4 requirement, has the reader pick one distro, edit that distro's `/etc/wsl.conf` to set `[boot] systemd=true`, run `wsl --shutdown` from Windows and restart the distro, then confirm `systemd` is PID 1 (matching `check_wsl_pid1`, `doctor.sh:276`, dispatched from `check_platform_contract` for `is_wsl()`-true Linux, `doctor.sh:248`/`doctor.sh:286`). Installs Tailscale inside the distro via the distro's own Linux package manager (Ubuntu/apt path, since WSL2's default distro is Ubuntu; note other distros follow their own manager per `node-linux.md`), enables `tailscaled` under `systemd`, runs `sudo tailscale up --ssh`, installs `tmux`/`claude`/`git`, clones the repo to `$HOME/agentic-workstation` inside the distro, sets `NODE_ROLE=host` in `config/local.env`, creates `$WORKSPACES_DIR`, and ends with `scripts/doctor.sh` exiting 0 with no `FAIL` line, where `platform-contract` must read `PASS` (systemd is PID 1). Adds a distinct "unattended reachability" section documenting, explicitly as **outside this repo**: `%UserProfile%\.wslconfig` with `[wsl2] vmIdleTimeout=-1` and `instanceIdleTimeout=-1`, an at-logon Task Scheduler entry running `wsl.exe -d <distro> --exec sleep infinity`, and disabling Windows sleep/no-activity power settings — and flags `instanceIdleTimeout`'s WSL-version requirement as an assumption to verify on the host. States the Windows-side Tailscale app is optional (client role only) and not required for the distro to act as its own tailnet host. Uses `<distro>`/`<node>`/`<user>` placeholders only, no real hostname/IP/username, no auth key. States the same default check-mode tailnet ACL is sufficient, no policy file committed. No step touches or reconfigures any other node.

**Ask First:** None expected — this is a documentation-only story with no script changes (`doctor.sh`'s WSL support — `is_wsl`, `check_wsl_pid1` — already ships from story 1.2).

**Never:** Do not modify `scripts/doctor.sh` or any other script. Do not commit an ACL policy file, an auth key, or any real host/IP/username. Do not write the WSL-as-client guide (`docs/node-client.md` covers that in Story 1.6) — this story is host enrollment only. Do not add a step that reconfigures or connects to a second node. Do not claim to have run an actual restart-and-reconnect test — the "unattended reachability" AC depends on real Windows hardware this agent doesn't have; document the steps and let `doctor.sh`'s all-clear be the verifiable proxy, same as the manual-checks-only precedent in `node-linux.md`/`node-macos.md`.

</frozen-after-approval>

## Code Map

- `docs/node-wsl.md` -- new file, the guide (AC target path, per epics.md Story 1.5).
- `docs/node-linux.md` -- structural/tone reference to mirror (Conventions block, numbered install→verify→ACL→cross-node→recovery flow, `ss -tlnp` security check).
- `docs/node-macos.md` -- reference for the "platform-contract must PASS, not SKIP" framing pattern (WSL is the second host type, after macOS, where this diverges from native Linux's SKIP).
- `scripts/doctor.sh` -- read-only reference: `is_wsl()` (`doctor.sh:248`), `check_wsl_pid1()` (`doctor.sh:276`), `check_platform_contract()` dispatch (`doctor.sh:286`) which calls `check_wsl_pid1` when `is_wsl()` is true on Linux; plus the shared host checks: `check_tailscale_installed` (`doctor.sh:134`), `check_tailnet_membership` (`doctor.sh:149`), `check_tailscale_ssh_advertised` (`doctor.sh:222`), `check_workspaces_dir` (`doctor.sh:239`), `check_ssh_dir_perms`/`check_ssh_key_perms` (`doctor.sh:166`/`doctor.sh:181`).
- `config/local.env.example` -- reference for the exact vars the guide's `config/local.env` step sets (`NODE_ROLE`, `WORKSPACES_DIR`).
- `.gitleaks.toml` -- read-only; confirms `<distro>`/`<node>`/`<user>` placeholder tokens are already allowlisted.

## Tasks & Acceptance

**Execution:**
- [x] `docs/node-wsl.md` -- write the guide: `wsl --version` check -> pick one distro -> `/etc/wsl.conf` `systemd=true` -> `wsl --shutdown` + restart -> confirm `systemd` PID 1 -> install Tailscale in distro -> enable `tailscaled` under systemd -> `sudo tailscale up --ssh` -> install `tmux`/`claude`/`git` -> clone repo -> `config/local.env` `NODE_ROLE=host` -> create `$WORKSPACES_DIR` -> `scripts/doctor.sh` (exit 0, no FAIL, `platform-contract` PASS) -- FR1, FR2, FR13, AC1
- [x] `docs/node-wsl.md` -- add "unattended reachability" section: `.wslconfig` (`vmIdleTimeout=-1`, `instanceIdleTimeout=-1`), Task Scheduler at-logon `wsl.exe -d <distro> --exec sleep infinity`, no-sleep power settings, flag `instanceIdleTimeout` version requirement as an assumption to verify -- AD-5, AC2, AC3
- [x] `docs/node-wsl.md` -- state Windows-side Tailscale app is optional (client role only), placeholders only, no other node touched -- OQ6, AC4
- [x] `docs/node-wsl.md` -- add default-ACL statement, cross-node verification (`tailscale ssh`/`ssh`), security check, and `tailscaled`-restart recovery caveat, mirroring `node-linux.md`/`node-macos.md` -- FR1, consistency with prior guides

**Acceptance Criteria:**
- Given Windows with WSL >= 2.4.4 (verified with `wsl --version`), when I follow `docs/node-wsl.md`, then one distro is chosen, `/etc/wsl.conf` has `[boot] systemd=true`, after `wsl --shutdown` systemd is PID 1, Tailscale is installed inside the distro with `tailscaled` enabled under systemd, and `tailscale up --ssh` makes the distro appear as its own tailnet node with its own MagicDNS name (OQ6).
- Given the Windows side, then the guide covers, outside the repo: `%UserProfile%\.wslconfig` with `vmIdleTimeout=-1`/`instanceIdleTimeout=-1`, an at-logon Task Scheduler entry, and no-sleep power settings (AD-5), and flags the `instanceIdleTimeout` version requirement as an assumption to verify.
- Given the Windows PC restarts and the user logs on, when no one touches the desktop, then the guide documents that within a few minutes another node can `tailscale ssh <user>@<node>` into the distro.
- Given the distro, when I clone to `$HOME/agentic-workstation`, set `NODE_ROLE=host`, create `$WORKSPACES_DIR`, and run `doctor.sh`, then all checks PASS including the WSL `platform-contract` check, and the guide states the Windows-side Tailscale app is optional (client role only), uses placeholders only, and touches no other node.

## Design Notes

`platform-contract` diverges a third way here: native Linux always `SKIP`s it, macOS requires `PASS` via a Homebrew-daemon-path check, and WSL requires `PASS` via `check_wsl_pid1` checking `systemd` is PID 1 — a `FAIL` means `/etc/wsl.conf` wasn't set or the distro wasn't restarted with `wsl --shutdown`. Unlike the Linux/macOS guides, the "unattended reachability" AC (survives a Windows restart with nobody touching the desktop) depends entirely on Windows-side settings (`.wslconfig`, Task Scheduler, power plan) that no script in this repo touches or can verify — the guide documents those steps, but the only automatable verification remains `doctor.sh`'s all-clear inside the distro itself.

## Verification

**Manual checks (if no CLI):**
- `docs/node-wsl.md` exists, uses only `<distro>`/`<node>`/`<user>` placeholders (no real hostnames/IPs), and every command block is copy-pasteable as written.
- Cross-check each doc step's commands/flags against the real `scripts/doctor.sh` checks listed in Code Map -- no invented flag or check name; confirm the doc correctly calls out `platform-contract` as PASS-required (via `systemd` PID 1) for WSL.
- `gitleaks git` (or the pre-commit hook) reports zero findings on the new file.

## Suggested Review Order

**Enrollment path (entry point)**

- WSL-version check, distro pick, and the systemd-enablement sequence that makes `platform-contract` PASS possible — the guide's core prerequisite chain.
  [`node-wsl.md:24`](../../docs/node-wsl.md#L24)

- `[boot]`-section guard added post-review so re-running this step never duplicates the block, mirroring the same guard applied to `.wslconfig` below.
  [`node-wsl.md:52`](../../docs/node-wsl.md#L52)

- Tailscale install inside the distro, `tailscaled` enabled under systemd, then `tailscale up --ssh` — the distro becomes its own tailnet node here.
  [`node-wsl.md:96`](../../docs/node-wsl.md#L96)

**`doctor.sh` all-clear contract (WSL-specific twist)**

- `platform-contract`'s three-way divergence (native Linux SKIP, macOS PASS via Homebrew daemon, WSL PASS via `check_wsl_pid1`) is the one place this guide diverges from both prior host guides.
  [`node-wsl.md:203`](../../docs/node-wsl.md#L203)

**Unattended reachability (new section, unique to this story)**

- The Windows-side `.wslconfig`/Task Scheduler/power-settings trio, explicitly framed as outside this repo's verification surface — `doctor.sh` can't check any of it.
  [`node-wsl.md:229`](../../docs/node-wsl.md#L229)

- `instanceIdleTimeout` version-requirement assumption, flagged per the story's AC rather than silently assumed.
  [`node-wsl.md:253`](../../docs/node-wsl.md#L253)

**Cross-node access and ACL**

- Default check-mode ACL is sufficient; no policy file committed -- ties to the epic's no-policy-file constraint.
  [`node-wsl.md:298`](../../docs/node-wsl.md#L298)

- `tailscale ssh`/`ssh` cross-node verification plus check-mode re-auth explanation, identical pattern to the Linux/macOS guides.
  [`node-wsl.md:305`](../../docs/node-wsl.md#L305)

**Security verification**

- `ss -tlnp` port check, with a WSL2-specific NAT-exposure callout not present in the Linux guide.
  [`node-wsl.md:329`](../../docs/node-wsl.md#L329)

**Recovery caveat**

- `tailscaled`-restart recovery: check status/logs, restart, then the `tailscale serve --tcp 2222 22` shim as last resort, scoped explicitly to "this distro only."
  [`node-wsl.md:362`](../../docs/node-wsl.md#L362)

**Peripherals**

- Windows-side Tailscale app is optional (client role only) -- answers OQ6 directly.
  [`node-wsl.md:290`](../../docs/node-wsl.md#L290)

- Conventions block, including the two placeholders (`<distro-codename>`, `<repo-url>`) added post-review.
  [`node-wsl.md:10`](../../docs/node-wsl.md#L10)
