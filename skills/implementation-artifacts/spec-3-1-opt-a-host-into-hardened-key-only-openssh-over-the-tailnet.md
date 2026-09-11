---
token_cost: {input: 22847, output: 12311, cache_read: 4670117, total: 4705275}
final_revision: '6527efaecd4f07ebf2d656e24aea4377422a1888'
title: 'Opt a host into hardened key-only OpenSSH over the tailnet'
type: 'feature'
created: '2026-09-11'
status: 'done'
review_loop_iteration: 1
context: []
baseline_commit: 'af23fd96cbd1e03b8e145f96e72547061c95909c'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Some hosts (e.g. a Mac keeping the Tailscale GUI app) can't serve Tailscale SSH, leaving them unreachable and breaking the "any node to any node" goal.

**Approach:** Give such a host a documented, strictly opt-in fallback — hardened, key-only OpenSSH reachable only over the tailnet, gated by `FALLBACK_SSHD=1` — plus matching `doctor.sh` checks that verify the hardening and SKIP correctly based on the flag.

## Boundaries & Constraints

**Always:** `FALLBACK_SSHD` (`config/local.env`, default `0`) is the only toggle — no auto-detection. When `1`: sshd runs with `PasswordAuthentication no`, `PermitRootLogin no`, `KbdInteractiveAuthentication no`, `AllowUsers <user>`, verified via `sshd -T`; `~/.ssh` is 0700 and `~/.ssh/authorized_keys` is 0600; the existing "Tailscale SSH advertised" check SKIPs; new checks (sshd running, four hardening settings, key permissions) run and are host-role-gated (SKIP on `client`). When `0` (default): new checks SKIP, existing "Tailscale SSH advertised" check runs unchanged. Reachability comes solely from the tailnet boundary (no public port-forward, no `ListenAddress` pinning). The host still runs `tailscale up` without `--ssh`. Docs use placeholders only (`<user>`), no real hostnames/IPs/keys.

**Ask First:** none anticipated.

**Never:** No `scripts/enroll.sh`, no client-key enrollment, no `connect.sh --fallback` — that is Story 3.2. No ACL policy file. No weakening of the Tailscale-SSH-primary path.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fallback disabled (default) | `FALLBACK_SSHD=0` or unset, role host/both | New checks SKIP; `check_tailscale_ssh_advertised` runs as today | N/A |
| Fallback enabled, hardened | `FALLBACK_SSHD=1`, sshd running with all 4 settings correct, `~/.ssh` 0700, `authorized_keys` 0600 | `tailscale-ssh-advertised` SKIP; sshd-running PASS; hardening PASS; key-perms PASS | N/A |
| Fallback enabled, one setting wrong | `FALLBACK_SSHD=1`, e.g. `PermitRootLogin yes` | Hardening check FAILs, names the offending setting | Non-zero exit via existing FAIL_COUNT convention |
| Fallback enabled, sshd not running | `FALLBACK_SSHD=1`, no sshd process/socket | sshd-running check FAILs | Non-zero exit |
| Fallback enabled, bad permissions | `FALLBACK_SSHD=1`, `authorized_keys` mode 0644 | key-perms check FAILs | Non-zero exit |
| Client role | `NODE_ROLE=client`, any `FALLBACK_SSHD` | All host-only checks (existing and new) SKIP, unchanged | N/A |

</frozen-after-approval>

## Code Map

- `scripts/doctor.sh` -- `check_tailscale_ssh_advertised()` (L222-237): SKIP this when `FALLBACK_SSHD=1`. `run_host_checks()` (L306-319): `case "$ROLE" in host|both) ... esac` is where new checks are dispatched, branching on `FALLBACK_SSHD`. `resolve_and_validate_role()` (L89-119): sourcing pattern (`set +eu` / `. "$CONFIG_FILE"` / `set -eu`) and default-via-`${VAR:-default}` convention (L118, `WORKSPACES_DIR`) to reuse for `FALLBACK_SSHD`. `emit()` (L45-55): PASS/FAIL/SKIP convention, only FAIL increments `FAIL_COUNT`. `write_stub_tools()` (L325-402): heredoc-stub pattern per external tool (`tailscale`, `uname`, `pgrep`, ...) gated by `DOCTOR_STUB_*` env vars, `chmod +x` at L400 -- add a new `sshd` stub here (and a process/socket check helper, e.g. via the existing `pgrep` stub) following the same pattern. `selftest_case_*` functions (e.g. L545-567) + registration in `run_self_test()` (L686-712): add new `selftest_case_fallback_sshd_*` cases here, one per I/O Matrix row.
- `config/local.env.example` -- `FALLBACK_SSHD=0` already declared (L7-8) with a comment; no change needed.
- `docs/node-linux.md` -- style precedent: numbered `## N. <step>` sections then thematic `##` sections, a `## Caveat: ...` label for known limitations (L206-246), existing manual `sshd -T` (L197) and `ss -tlnp` (L183) snippets to align with, doctor.sh referenced by check name not line number (L136-143).
- `docs/node-macos.md` -- L90-91 already forward-references this story's guide ("ships as its own guide in Epic 3") -- update that placeholder to link `docs/fallback-openssh.md` once it exists.
- `docs/fallback-openssh.md` -- NEW FILE, this story's main doc deliverable.
- `scripts/doctor.sh` -- `check_platform_contract()` (L286-304) dispatches `check_macos_backend()` on Darwin, which hard-requires the Homebrew `tailscaled` backend and FAILs on the Tailscale GUI app's backend. This directly conflicts with the exact host this story's fallback targets (a Mac that must keep the GUI app -- see epic-3-context.md Goal). `run_host_checks()` must SKIP the macOS-backend requirement (not the whole platform-contract check -- Linux/WSL platform checks still apply) when `FALLBACK_SSHD=1`, mirroring `check_tailscale_ssh_advertised`'s existing SKIP pattern.

## Tasks & Acceptance

**Execution:**
- [x] `scripts/doctor.sh` -- read `FALLBACK_SSHD` (default `0`) in the role-resolution sourcing block; add `check_sshd_running()`, `check_sshd_hardening()`, `check_authorized_keys_perms()` (renamed from the spec's `check_ssh_key_perms()` -- that name already exists as a pre-existing common check for `~/.ssh/id_*` private-key permissions; reusing it would have collided); wire `run_host_checks()` to SKIP `check_tailscale_ssh_advertised` and run the three new checks when `FALLBACK_SSHD=1`, and to SKIP the three new checks (unchanged existing check) when `FALLBACK_SSHD=0` -- implements FR15/AD-3's SKIP-symmetry requirement
- [x] `scripts/doctor.sh` -- add an `sshd` stub to `write_stub_tools()` (emitting canned `sshd -T` key=value output controlled by `DOCTOR_STUB_SSHD_*` vars) and a way to simulate sshd running/not-running -- needed so the self-test stays hermetic (no real sshd touched)
- [x] `scripts/doctor.sh` -- add `selftest_case_fallback_sshd_*` covering every I/O Matrix row, registered in `run_self_test()`
- [x] `docs/fallback-openssh.md` -- write the host-setup guide (macOS Remote Login, Linux/WSL `openssh-server`), the four hardening settings + `sshd -T` verification, `~/.ssh` permissions, `FALLBACK_SSHD=1` in `config/local.env`, explicit "documented exception" framing, tailnet-only reachability note, `tailscale up` without `--ssh` -- satisfies this story's AC
- [x] `docs/node-macos.md` -- update the forward-reference placeholder to link `docs/fallback-openssh.md`
- [x] `scripts/doctor.sh` -- make `check_macos_backend()`'s Homebrew-`tailscaled` requirement SKIP when `FALLBACK_SSHD=1` (Linux/WSL platform-contract checks are unaffected); add a `selftest_case_fallback_sshd_macos_gui_app` case (`DOCTOR_STUB_UNAME=Darwin`, GUI-app backend path, `FALLBACK_SSHD=1`) asserting `platform-contract` does not FAIL -- closes the bad_spec found in review: this story's whole premise is a Mac keeping the GUI app, which must not permanently FAIL `doctor.sh`
- [x] `scripts/doctor.sh` -- `check_sshd_hardening()`: also recognize the pre-OpenSSH-8.7 `ChallengeResponseAuthentication` alias for `KbdInteractiveAuthentication` (older Ubuntu/RHEL sshd, which this guide explicitly supports, would otherwise always FAIL); tighten `AllowUsers` to reject empty/wildcard/multi-user values (currently any non-empty value PASSes, including `*` or multiple users, which defeats "one login account"); check for `sshd`'s binary at common sbin paths in addition to `command -v` (sshd is rarely on a non-root user's PATH) -- add/extend selftest cases for each of these three branches
- [x] `scripts/doctor.sh` -- `check_authorized_keys_perms()`: fix the early-return path so a bad `~/.ssh` permission is still reported when `authorized_keys` is also missing (currently silently dropped)
- [x] `scripts/doctor.sh` -- `run_host_checks()`'s `FALLBACK_SSHD`-not-`1` SKIP messages currently hardcode the literal text `FALLBACK_SSHD=0`; interpolate the actual value instead

**Acceptance Criteria:**
- Given `docs/fallback-openssh.md` followed on macOS or Linux/WSL, when sshd is configured as documented, then `sshd -T` confirms all four hardening settings and the guide states reachability is tailnet-bounded, not `ListenAddress`-pinned
- Given `config/local.env` with `FALLBACK_SSHD=1`, when `doctor.sh` runs on that host, then "Tailscale SSH advertised" is SKIP and the three new checks run (PASS/FAIL based on real state)
- Given `FALLBACK_SSHD=0` (default), when `doctor.sh` runs, then the three new checks SKIP and "Tailscale SSH advertised" behaves as before
- Given the guide, then it is labelled the documented exception, uses placeholders only, commits no key material, and states the host still joins the tailnet normally

## Spec Change Log

- **Finding (bad_spec, review_loop_iteration 1):** two independent reviewers (blind-hunter, verification-gap) confirmed `check_platform_contract()`'s macOS-backend requirement (`check_macos_backend()`, pre-existing since story 1.2) still FAILs when the host runs the Tailscale GUI app -- which is the exact host type this story's fallback exists for (see epic-3-context.md Goal: "a Mac that keeps the GUI app instead of the open-source `tailscaled` variant"). The original Code Map only pointed at `check_tailscale_ssh_advertised`; it never told the implementer that `check_macos_backend`'s requirement conflicts with this story's premise.
  **Amended:** Code Map and Tasks now explicitly call out that `check_macos_backend`'s Homebrew-`tailscaled` requirement must SKIP when `FALLBACK_SSHD=1`, mirroring the existing `check_tailscale_ssh_advertised` SKIP pattern. Linux/WSL platform-contract checks are unaffected.
  **Known-bad state avoided:** a host correctly following `docs/fallback-openssh.md` end-to-end would see `doctor.sh` permanently report `FAIL platform-contract` with no path to green, contradicting the guide's own "Verify with doctor.sh" section.
  **KEEP:** the existing `check_sshd_running`, `check_sshd_hardening`, `check_authorized_keys_perms` implementations, their stubs, and their selftest cases from iteration 1 are correct in shape and must be preserved as-is; only add the platform-contract interaction, the three `check_sshd_hardening`/`AllowUsers`/PATH robustness patches, and the `check_authorized_keys_perms` message-drop fix listed as new/updated tasks above. Do not rewrite unrelated passing code.

## Design Notes

Mirror `check_platform_contract()`'s OS-dispatch shape only if a hardening check genuinely needs to branch on macOS vs. Linux `sshd -T` output; otherwise keep the three new checks OS-agnostic since `sshd -T` output format is consistent across OpenSSH implementations. Key-permission check reuses the same `stat`-based approach `doctor.sh` likely already uses elsewhere for permission checks (verify during implementation) rather than inventing a new one.

## Verification

**Commands:**
- `shellcheck scripts/doctor.sh` -- expected: no warnings
- `scripts/doctor.sh --check` -- expected: PASS on all existing + new self-test cases
- `gitleaks protect --staged` (pre-commit hook) -- expected: clean, no key material committed

**Manual checks (if no CLI):**
- `docs/fallback-openssh.md` reads coherently end-to-end and cross-links resolve (node-macos.md, node-linux.md, node-wsl.md as applicable)

## Suggested Review Order

**SKIP symmetry between the two auth paths**

- Entry point: the flag itself, defaulted like every other config var in this function.
  [`doctor.sh:93`](../../scripts/doctor.sh#L93)

- Existing Tailscale-SSH check now SKIPs in favor of the documented fallback.
  [`doctor.sh:224`](../../scripts/doctor.sh#L224)

- The bad_spec fix: macOS-backend requirement SKIPs too, since the GUI-app Mac is this story's whole premise.
  [`doctor.sh:296`](../../scripts/doctor.sh#L296)

- Dispatches the three new checks only when the flag is set, SKIPs them (with the real value interpolated) otherwise.
  [`doctor.sh:423`](../../scripts/doctor.sh#L423)

**New hardening checks**

- Verifies sshd is actually running before trusting its config.
  [`doctor.sh:319`](../../scripts/doctor.sh#L319)

- Core logic: sbin-path fallback, the pre-8.7 ChallengeResponseAuthentication alias, and AllowUsers empty/wildcard/multi rejection.
  [`doctor.sh:327`](../../scripts/doctor.sh#L327)

- Permission check with the combined-failure fix — a bad `~/.ssh` mode is no longer dropped when `authorized_keys` is also missing.
  [`doctor.sh:393`](../../scripts/doctor.sh#L393)

**Guide deliverable**

- Frames the whole doc as an explicit, opt-in exception to the primary Tailscale-SSH path.
  [`fallback-openssh.md:3`](../../docs/fallback-openssh.md#L3)

- States reachability comes from the tailnet boundary, never a `ListenAddress` pin or port-forward — the AC's core safety claim.
  [`fallback-openssh.md:186`](../../docs/fallback-openssh.md#L186)

- Forward-reference from the sibling macOS guide now resolves to a real file.
  [`node-macos.md:91`](../../docs/node-macos.md#L91)

**Test coverage (peripheral)**

- Representative case: hardened path with all four settings correct, permissions right, over both roles' SKIP/PASS split.
  [`doctor.sh:860`](../../scripts/doctor.sh#L860)

- The case that specifically proves the platform-contract bad_spec fix: GUI-app backend + fallback on, no FAIL.
  [`doctor.sh:1031`](../../scripts/doctor.sh#L1031)

- Client-role SKIP-everything case, confirming the fallback checks respect the same role gate as the rest of `run_host_checks`.
  [`doctor.sh:1004`](../../scripts/doctor.sh#L1004)
