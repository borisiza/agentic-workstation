---
token_cost: {input: 149396, output: 58285, cache_read: 7397197, total: 7604878}
final_revision: '40e571687f8efc53cb7228c159af2d9f93ccca98'
title: 'Enroll a Linux host'
type: 'feature'
created: '2026-09-11'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '30dd898521c27822e4e43cc59aced4b9ca7f6f7a'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A Linux machine has no documented path to join the mesh as a Tailscale SSH host, so the owner cannot reproducibly onboard a new Linux node or verify it is safe (identity-only SSH, no password/root login, no public exposure).

**Approach:** Add `docs/node-linux.md`, a placeholder-only, copy-pasteable guide covering install → `tailscale up --ssh` → tool install → repo clone → role config → `doctor.sh` all-PASS → cross-node verification → the `ss -tlnp` security check → the `tailscaled`-restart recovery caveat.

## Boundaries & Constraints

**Always:** Guide installs Tailscale 1.102.3 from the official apt/yum repo, then `tailscale up --ssh`. It installs `tmux`, `claude` (Claude Code CLI), `git`; clones the repo to `$HOME/agentic-workstation`; copies `config/local.env.example` to `config/local.env` with `NODE_ROLE=host`; creates `$WORKSPACES_DIR`; ends with `scripts/doctor.sh` reporting no `FAIL` lines (exit 0) — `SKIP` is expected for checks that don't apply, e.g. `platform-contract` on native (non-WSL) Linux always emits `SKIP`, never `PASS` (`doctor.sh:286`), mirroring how the client role SKIPs host-only checks. Uses `<node>`/`<user>` placeholders only — no real hostname, IP, or tailnet name. States the default tailnet ACL (`autogroup:member -> autogroup:self`, check mode) is sufficient; no policy file is committed. Documents verifying from another node with `tailscale ssh <user>@<node>` (fallback: plain `ssh <user>@<node>`) getting a shell with no password/key prompt, plus the check-mode browser re-auth flow. Documents the `ss -tlnp` verification step confirming no sshd listens on a non-tailnet interface and that password/root login are impossible. Documents the `tailscaled`-restart caveat and the `tailscale serve --tcp 2222 22` manual recovery shim. No step instructs touching or reconfiguring any other node.

**Ask First:** None expected — this is a documentation-only story with no script changes.

**Never:** Do not commit an ACL policy file, an auth key, or any real host/IP/username. Do not modify `scripts/doctor.sh` or any other script (unchanged from story 1.2). Do not add a step that reconfigures or connects to a second node.

</frozen-after-approval>

## Code Map

- `docs/node-linux.md` -- new file, the guide (AC target path, per epics.md Story 1.3).
- `scripts/doctor.sh` -- read-only reference; guide's final step must match its real checks: `check_tailscale_installed` (>=1.102, `doctor.sh:134`), `check_tailnet_membership` (`doctor.sh:149`), `check_tailscale_ssh_advertised` via `tailscale debug prefs` `RunSSH:true` (`doctor.sh:222`), `check_workspaces_dir` (`doctor.sh:239`), `check_ssh_dir_perms`/`check_ssh_key_perms` (`doctor.sh:166`, `doctor.sh:181`). Plain Linux (non-WSL) has no extra `check_platform_contract` gate (`doctor.sh:286`) -- do not invent one in the doc.
- `config/local.env.example` -- reference for the exact vars the guide's `config/local.env` step sets (`NODE_ROLE`, `WORKSPACES_DIR`, `FALLBACK_SSHD`, `SSH_USER`).
- `README.md` -- reference only, for the placeholder-token and public-repo-rules convention (`<node>`, `<user>`) the guide must follow; not modified by this story (README's doc index/links land in Story 1.6).
- `.gitleaks.toml` -- read-only; confirms placeholder tokens used in the guide are already allowlisted, so no new allowlist entry is needed.

## Tasks & Acceptance

**Execution:**
- [x] `docs/node-linux.md` -- write the guide: install Tailscale 1.102.3 (official repo) -> `tailscale up --ssh` -> install `tmux`/`claude`/`git` -> clone repo to `$HOME/agentic-workstation` -> `config/local.env` with `NODE_ROLE=host` -> create `$WORKSPACES_DIR` -> run `scripts/doctor.sh` (no FAIL lines, exit 0; SKIP expected for platform-contract on native Linux) -- FR1, FR2, FR13, AC1
- [x] `docs/node-linux.md` -- add the default-ACL statement (no policy file committed) and placeholder-only convention note -- FR2, FR13, AC2
- [x] `docs/node-linux.md` -- add cross-node verification section: `tailscale ssh <user>@<node>` / `ssh <user>@<node>` shell with no prompt, plus check-mode browser re-auth explanation -- FR1, AC3
- [x] `docs/node-linux.md` -- add `ss -tlnp` security verification step (no non-tailnet sshd listener, no password/root login) -- FR3, NFR1, AC4
- [x] `docs/node-linux.md` -- add `tailscaled`-restart caveat and `tailscale serve --tcp 2222 22` recovery shim, and state no other node is touched -- NFR6, AC5

**Acceptance Criteria:**
- Given a fresh supported Linux machine, when I follow `docs/node-linux.md`, then I install Tailscale 1.102.3, run `tailscale up --ssh`, install `tmux`/`claude`/`git`, clone to `$HOME/agentic-workstation`, create `config/local.env` with `NODE_ROLE=host`, create `$WORKSPACES_DIR`, and `scripts/doctor.sh` exits 0 with no `FAIL` line (`platform-contract` correctly SKIPs on native Linux).
- Given the guide, then it uses `<node>`/`<user>` placeholders only, contains no auth key, and states the default tailnet ACL is sufficient with no policy file committed.
- Given the host is enrolled, when another tailnet node runs `tailscale ssh <user>@<node>` (or `ssh <user>@<node>`), then a shell opens with no password/key prompt, and the guide explains check-mode re-authentication.
- Given the enrolled host, when I run the documented `ss -tlnp` check, then no sshd listens on a non-tailnet interface and password/root login are impossible.
- Given the guide, then it documents the `tailscaled`-restart caveat and the manual `tailscale serve --tcp 2222 22` recovery shim, and no step touches any other node.

## Design Notes

`tailscale debug prefs` is the same mechanism `doctor.sh` uses to verify SSH is advertised (`RunSSH: true`) -- the guide's own verification step should tell the reader to just run `scripts/doctor.sh` rather than re-deriving `tailscale debug prefs` by hand, keeping one source of truth for "am I ready." The `ss -tlnp` check is a manual step (not scriptable in `doctor.sh` without a new check) since it validates the operator's own sshd config choice, not a mesh precondition.

## Spec Change Log

- **Finding:** verification-gap review found the frozen Boundaries/AC text ("`scripts/doctor.sh` reporting all PASS") is unreachable on native (non-WSL) Linux: `check_platform_contract` (`doctor.sh:286`) always emits `SKIP` for `platform-contract` there, never `PASS`, so the doc's own stated completion rule could never be satisfied by the host it targets.
  **Amended:** replaced "all PASS" wording in Boundaries, the execution task, and the first Acceptance Criterion with doctor.sh's actual contract — exit 0, no `FAIL` line, `SKIP` expected for checks that don't apply (matching the `usage()`/story-1.2 contract and the client-role SKIP precedent already in the AC).
  **Known-bad state avoided:** a reader following the guide on a real native-Linux host would see the one structurally-mandatory `SKIP platform-contract` line and conclude enrollment failed, with no fix hint to follow because there is none.
  **KEEP:** all other Boundaries/AC content (placeholders-only, no auth key, default-ACL statement, cross-node verification, `ss -tlnp` check, `tailscaled`-restart caveat) is correct and must survive re-derivation unchanged.

## Verification

**Manual checks (if no CLI):**
- `docs/node-linux.md` exists, uses only `<node>`/`<user>` placeholders (no real hostnames/IPs), and every command block is copy-pasteable as written.
- Cross-check each doc step's commands/flags against the real `scripts/doctor.sh` checks listed in Code Map -- no invented flag or check name.
- `gitleaks git` (or the pre-commit hook) reports zero findings on the new file.

## Suggested Review Order

**Enrollment path (entry point)**

- Install → `tailscale up --ssh` → tool install → clone/config → `doctor.sh`, the guide's core sequence.
  [`node-linux.md:18`](../../docs/node-linux.md#L18)

- Completion criterion corrected post-review: exit 0 / no `FAIL`, not "all PASS" -- `platform-contract` always SKIPs on native Linux.
  [`node-linux.md:136`](../../docs/node-linux.md#L136)

**Security verification**

- `ss -tlnp` now run with `sudo` so process attribution actually works, plus `sshd -T` to catch config drop-in overrides.
  [`node-linux.md:176`](../../docs/node-linux.md#L176)

**Cross-node access and ACL**

- Default check-mode ACL is sufficient; no policy file committed -- ties to the epic's no-policy-file constraint.
  [`node-linux.md:145`](../../docs/node-linux.md#L145)

- `tailscale ssh`/`ssh` cross-node verification plus check-mode re-auth explanation.
  [`node-linux.md:152`](../../docs/node-linux.md#L152)

**Recovery caveat**

- `tailscaled`-restart recovery: troubleshoot first (`systemctl status`/`journalctl`), then the `tailscale serve --tcp 2222 22` shim, with the total-lockout case called out explicitly.
  [`node-linux.md:206`](../../docs/node-linux.md#L206)

**Peripherals**

- Package-manager edge cases: distro/arch line selection, missing `yum-config-manager`.
  [`node-linux.md:23`](../../docs/node-linux.md#L23)
