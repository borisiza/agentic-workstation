---
title: 'Enroll a macOS host'
type: 'feature'
created: '2026-09-11'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '0ca6552aa0d63002dc87e9b17de9e7f8bb0da914'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A Mac running the Standalone/App Store Tailscale GUI app has no documented path to join the mesh as a Tailscale SSH host, since that app has no SSH server (OQ7) — only the open-source `tailscaled` (Homebrew formula) serves Tailscale SSH.

**Approach:** Add `docs/node-macos.md`, mirroring `docs/node-linux.md`'s structure: quit/uninstall the GUI app → install Homebrew `tailscale` → `brew services start tailscale` → `tailscale up --ssh` → tool install → repo clone → role config → `doctor.sh` all-clear (including the macOS `platform-contract` PASS) → cross-node verification → Remote Login check → the same tailnet-ACL and recovery-caveat sections as the Linux guide.

## Boundaries & Constraints

**Always:** Guide states the Mac must be running the Standalone/App Store Tailscale app first, then: quit/uninstall it, `brew install tailscale`, `brew services start tailscale` (launchd-managed, root, survives reboot), `sudo tailscale up --ssh`, install `tmux`/`claude`/`git` (Homebrew), clone repo to `$HOME/agentic-workstation`, copy `config/local.env.example` to `config/local.env` with `NODE_ROLE=host`, create `$WORKSPACES_DIR`, end with `scripts/doctor.sh` exiting 0 with no `FAIL` line, where `platform-contract` must read `PASS` (not `SKIP`) on macOS since `check_macos_backend` (`doctor.sh:258`) is the one host-only check that actively asserts Homebrew `tailscaled` (path under `/opt/homebrew/*` or `/usr/local/*`) is the running backend, `FAIL`ing if the GUI app's own daemon is still active. States explicitly what is lost by dropping the GUI app (menu-bar status/toggle) and that a key-only OpenSSH fallback exists (FR18) for Macs that must keep the GUI — that fallback guide itself is out of scope, delivered in Epic 3. Documents cross-node verification (`tailscale ssh <user>@<node>`, fallback plain `ssh`) and that macOS Remote Login is not required on the primary path, verified off via `sudo lsof -iTCP -sTCP:LISTEN | grep -i ssh` (or confirmed absent). Notes bash 3.2 is sufficient (no script changes needed). Uses `<node>`/`<user>` placeholders only, no real hostname/IP/username, no auth key. States the same default check-mode tailnet ACL (`autogroup:member -> autogroup:self`) is sufficient, no policy file committed. No step touches or reconfigures any other node.

**Ask First:** None expected — this is a documentation-only story with no script changes (doctor.sh's macOS support already ships from story 1.2).

**Never:** Do not commit an ACL policy file, an auth key, or any real host/IP/username. Do not modify `scripts/doctor.sh` or any other script. Do not write the Epic-3 OpenSSH-fallback guide itself — only reference that it exists. Do not add a step that reconfigures or connects to a second node.

</frozen-after-approval>

## Code Map

- `docs/node-macos.md` -- new file, the guide (AC target path, per epics.md Story 1.4).
- `docs/node-linux.md` -- structural/tone reference to mirror (Conventions block, numbered install→verify→ACL→cross-node→recovery flow); do not copy Linux-specific package-manager content.
- `scripts/doctor.sh` -- read-only reference; guide's final step must match real checks: `check_tailscale_installed` (>=1.102, `doctor.sh:134`), `check_tailnet_membership` (`doctor.sh:149`), `check_tailscale_ssh_advertised` via `tailscale debug prefs` `RunSSH:true` (`doctor.sh:222`), `check_workspaces_dir` (`doctor.sh:239`), `check_ssh_dir_perms`/`check_ssh_key_perms` (`doctor.sh:166`, `doctor.sh:181`), and macOS-specific `check_macos_backend` (`doctor.sh:258`, dispatched from `check_platform_contract` at `doctor.sh:286` for `Darwin`) -- this is the one check in the whole suite that requires `PASS` (not `SKIP`) as part of "all-clear," since it's how the guide proves the GUI-app daemon was actually replaced.
- `config/local.env.example` -- reference for the exact vars the guide's `config/local.env` step sets (`NODE_ROLE`, `WORKSPACES_DIR`).
- `.gitleaks.toml` -- read-only; confirms placeholder tokens used in the guide are already allowlisted.

## Tasks & Acceptance

**Execution:**
- [x] `docs/node-macos.md` -- write the guide: quit/uninstall Tailscale GUI app -> `brew install tailscale` -> `brew services start tailscale` -> `sudo tailscale up --ssh` -> install `tmux`/`claude`/`git` -> clone repo -> `config/local.env` with `NODE_ROLE=host` -> create `$WORKSPACES_DIR` -> run `scripts/doctor.sh` (exit 0, no FAIL, `platform-contract` PASS) -- FR1, FR2, FR13, AC1/AC2
- [x] `docs/node-macos.md` -- state what's lost (menu-bar GUI) and reference the FR18 key-only OpenSSH fallback for Macs keeping the GUI (Epic 3 delivers that guide) -- OQ7, AC1
- [x] `docs/node-macos.md` -- add default-ACL statement (no policy file committed) and placeholder-only convention note -- FR2, FR13, AC2 (mirrors node-linux.md)
- [x] `docs/node-macos.md` -- add cross-node verification section (`tailscale ssh`/`ssh`) and document Remote Login is not required, verified off via `sudo lsof -iTCP -sTCP:LISTEN` -- FR1, AC3
- [x] `docs/node-macos.md` -- add bash-3.2-sufficient note and state no other node is touched -- AC4

**Acceptance Criteria:**
- Given a Mac running the Standalone/App Store Tailscale app, when I follow `docs/node-macos.md`, then I quit/uninstall the GUI app, install the Homebrew `tailscale` formula, start it with `brew services start tailscale`, run `tailscale up --ssh`, and the node shows Tailscale SSH advertised.
- Given the tailnet step is done, when I complete the remaining steps (clone, `config/local.env` with `NODE_ROLE=host`, `$WORKSPACES_DIR`, `doctor.sh`), then `doctor.sh` exits 0 with no `FAIL` line and `platform-contract` reads `PASS` (Homebrew `tailscaled` active).
- Given the enrolled Mac, when another node runs `tailscale ssh <user>@<node>`, then a shell opens with identity auth only, and macOS Remote Login is documented as not required and verified off with `sudo lsof -iTCP -sTCP:LISTEN`.
- Given the guide, then it notes bash 3.2 is sufficient, uses placeholders only, and touches no other node.

## Design Notes

The Linux guide's "don't re-derive checks by hand, just run `doctor.sh`" framing carries over unchanged, with one addition: unlike the Linux guide (where `platform-contract` always `SKIP`s and that's correctly documented as expected), the macOS guide must tell the reader `platform-contract` should read `PASS` here — a `FAIL` on that line means the GUI app's `tailscaled` is still the active daemon and needs to be quit before `brew services start tailscale` takes over as PID owner of the `tailscaled` process `pgrep` finds.

## Verification

**Manual checks (if no CLI):**
- `docs/node-macos.md` exists, uses only `<node>`/`<user>` placeholders (no real hostnames/IPs), and every command block is copy-pasteable as written.
- Cross-check each doc step's commands/flags against the real `scripts/doctor.sh` checks listed in Code Map -- no invented flag or check name; confirm the doc correctly calls out `platform-contract` as PASS-required (not SKIP) for macOS.
- `gitleaks git` (or the pre-commit hook) reports zero findings on the new file.

## Suggested Review Order

**Enrollment path (entry point)**

- GUI app quit/uninstall → Homebrew install+version-check → `brew services start` → `tailscale up --ssh`, the guide's core sequence.
  [`node-macos.md:24`](../../docs/node-macos.md#L24)

- Version-verify patch added post-review, mirroring node-linux.md's precedent so `doctor.sh`'s `>=1.102.0` floor is never a surprise.
  [`node-macos.md:45`](../../docs/node-macos.md#L45)

**`doctor.sh` all-clear contract (macOS-specific twist)**

- Completion criterion is the one place macOS diverges from Linux: `platform-contract` must read PASS, not SKIP, proving Homebrew's daemon replaced the GUI app's.
  [`node-macos.md:154`](../../docs/node-macos.md#L154)

**Security verification**

- Remote Login confirmed off via `sudo lsof -iTCP -sTCP:LISTEN`, the macOS analogue of node-linux.md's `ss -tlnp` check.
  [`node-macos.md:200`](../../docs/node-macos.md#L200)

**Cross-node access and ACL**

- Default check-mode ACL is sufficient; no policy file committed -- ties to the epic's no-policy-file constraint.
  [`node-macos.md:169`](../../docs/node-macos.md#L169)

- `tailscale ssh`/`ssh` cross-node verification plus check-mode re-auth explanation.
  [`node-macos.md:176`](../../docs/node-macos.md#L176)

**Recovery caveat**

- `tailscaled`-restart recovery: check first, inspect `log show`/Console.app, restart via `brew services`, then the `tailscale serve --tcp 2222 22` shim as last resort -- shim and log-check both added post-review to match node-linux.md's equivalent caveat.
  [`node-macos.md:227`](../../docs/node-macos.md#L227)

**Peripherals**

- What's lost by dropping the GUI app, and the FR18/Epic-3 OpenSSH-fallback pointer for Macs that must keep it.
  [`node-macos.md:81`](../../docs/node-macos.md#L81)

- bash 3.2 sufficiency note -- no script changes needed to run `doctor.sh` on macOS's stock bash.
  [`node-macos.md:221`](../../docs/node-macos.md#L221)
