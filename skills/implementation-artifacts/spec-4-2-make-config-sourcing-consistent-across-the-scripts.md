---
title: 'Make config sourcing consistent across the scripts'
type: 'bugfix'
created: '2026-09-13'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '39f61e129742db759a520f1689ef30e61ec058d7'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `doctor.sh` sources `config/local.env` directly in `resolve_and_validate_role`, so a shell syntax error in that file surfaces to stderr, while `connect.sh`, `enroll.sh`, `start-claude.sh`, `status.sh`, and `stop.sh` source it with `2>/dev/null`, hiding the shell's own error text — a malformed config is diagnosable from one script and silently opaque from another (FR17, epic-3-retro item 3).

**Approach:** Converge all five sibling scripts on `doctor.sh`'s already-correct form — drop `2>/dev/null` from their `. "$CONFIG_FILE"` call — and update each affected `selftest_case_broken_config` to assert on the die2 message's content instead of an exact stderr line count, since the raw shell syntax-error line now also reaches stderr alongside it.

## Boundaries & Constraints

**Always:** Keep `resolve_and_validate_role`'s existing `set +eu` / `source_rc=$?` / `set -eu` guard and its `die2 "config/local.env failed to load: ..."` message unchanged — only the redirection on the `.` line is removed. Role resolution precedence (`config/local.env` -> `$NODE_ROLE` -> flag, per script) is untouched.

**Ask First:** Nothing — the fix is mechanical and the target form (doctor.sh's) already exists and is proven in production.

**Never:** Do not touch `resolve_ssh_user` or any other function; do not add a shared library, `jq`, or Python (AD-8); do not change what `config/local.env` is used for, only how the source failure is reported.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Malformed config | `config/local.env` has a shell syntax error (e.g. unterminated `if`) | Every one of the six scripts prints the shell's own syntax-error line to stderr, then dies with `config/local.env failed to load: ...`, exit 2, role never set | Both lines land on stderr before any other side effect (no tmux/ssh/tailscale call) |
| Well-formed config | `config/local.env` sources cleanly | Unchanged: role resolves as before | N/A |

</frozen-after-approval>

## Code Map

- `scripts/connect.sh:105` -- `. "$CONFIG_FILE" 2>/dev/null` in `resolve_and_validate_role` -- drop `2>/dev/null`
- `scripts/enroll.sh:87` -- same pattern in `resolve_and_validate_role` -- drop `2>/dev/null`
- `scripts/start-claude.sh:89` -- same pattern in `resolve_and_validate_role` -- drop `2>/dev/null`
- `scripts/status.sh:59` -- same pattern in `resolve_and_validate_role` -- drop `2>/dev/null`
- `scripts/stop.sh:77` -- same pattern in `resolve_and_validate_role` -- drop `2>/dev/null`
- `scripts/doctor.sh:94` -- already `. "$CONFIG_FILE"` with no suppression -- reference form, no change; has no `selftest_case_broken_config` today
- `scripts/connect.sh:552`, `scripts/enroll.sh:541`, `scripts/start-claude.sh:385`, `scripts/status.sh:236`, `scripts/stop.sh:328` -- each script's `selftest_case_broken_config()` currently ends with `assert_stderr_one_line "$case_name" "$err" || ok=1`, which will start failing once the shell's own syntax-error line also reaches `$err` -- replace with `assert_file_contains "$case_name" "$err" "config/local.env" || ok=1`
- `scripts/connect.sh:313`, `scripts/enroll.sh:290`, `scripts/start-claude.sh:186`, `scripts/stop.sh:175` -- existing `assert_file_contains(case_name, file, pattern)` helper (fixed-string `grep -Fq`) -- reuse as-is, already present in four of the five sibling scripts
- `scripts/status.sh` -- lacks `assert_file_contains`; add it verbatim (copy from e.g. `scripts/stop.sh:175-181`) since `selftest_case_broken_config` needs it
- Verified empirically: sourcing `printf 'NODE_ROLE=host\nif [ \n'` produces exactly one shell stderr line (`<path>: line 3: syntax error: unexpected end of file from `if' command on line 2`) -- confirms the fix produces two clean stderr lines (shell line + die2 line), not a multi-line burst

## Tasks & Acceptance

**Execution:**
- [x] `scripts/connect.sh` -- remove `2>/dev/null` at L105; change `selftest_case_broken_config`'s assertion to `assert_file_contains` -- AC1/AC2
- [x] `scripts/enroll.sh` -- same two edits -- AC1/AC2
- [x] `scripts/start-claude.sh` -- same two edits -- AC1/AC2
- [x] `scripts/status.sh` -- same two edits, plus add the missing `assert_file_contains` helper -- AC1/AC2
- [x] `scripts/stop.sh` -- same two edits -- AC1/AC2

**Acceptance Criteria:**
- Given the six scripts in `scripts/`, when inspecting how each sources `$CONFIG_FILE` in `resolve_and_validate_role`, then all six use the identical unsuppressed form.
- Given a `config/local.env` with a deliberate syntax error, when running each of the six scripts, then every one fails exit 2 with stderr naming `config/local.env`, and none proceeds with an unset or partially-sourced role.
- Given the change, then all six `--check` self-tests pass, `doctor.sh --check` still aggregates the five siblings as PASS, and `shellcheck` stays clean on all six scripts.

## Spec Change Log

## Verification

**Commands:**
- `shellcheck scripts/connect.sh scripts/enroll.sh scripts/start-claude.sh scripts/status.sh scripts/stop.sh scripts/doctor.sh` -- expected: clean
- `scripts/connect.sh --check`, `scripts/enroll.sh --check`, `scripts/start-claude.sh --check`, `scripts/status.sh --check`, `scripts/stop.sh --check` -- expected: PASS each, including `broken-config`
- `scripts/doctor.sh --check` -- expected: PASS, all five `other-script:*` PASS

**Manual checks (if no CLI):**
- Read each edited `resolve_and_validate_role` and confirm the `.` line matches `doctor.sh`'s exact form (no trailing redirection).

## Suggested Review Order

**Sourcing form convergence**

- Reference form already in production; the target all five siblings now match.
  [`doctor.sh:94`](../../scripts/doctor.sh#L94)

- Drops `2>/dev/null` so a shell syntax error in `config/local.env` surfaces.
  [`connect.sh:105`](../../scripts/connect.sh#L105)

- Same one-line fix, `host|both` role gate instead of `client|both`.
  [`enroll.sh:87`](../../scripts/enroll.sh#L87)

- Same one-line fix.
  [`start-claude.sh:89`](../../scripts/start-claude.sh#L89)

- Same one-line fix.
  [`status.sh:59`](../../scripts/status.sh#L59)

- Same one-line fix.
  [`stop.sh:77`](../../scripts/stop.sh#L77)

**Self-test strengthening**

- New assertion distinguishes "shell diagnostic reached stderr" from "only the die2 message did" — closes a gap all three review layers flagged.
  [`connect.sh:568`](../../scripts/connect.sh#L568)

- Same two-assertion pattern.
  [`enroll.sh:556`](../../scripts/enroll.sh#L556)

- Same two-assertion pattern.
  [`start-claude.sh:402`](../../scripts/start-claude.sh#L402)

- `assert_file_contains` helper added here (didn't exist before this story) plus the same two-assertion pattern.
  [`status.sh:179`](../../scripts/status.sh#L179)

- Same two-assertion pattern.
  [`stop.sh:344`](../../scripts/stop.sh#L344)

- Comment updated to drop the now-false "one stderr line" claim.
  [`connect.sh:548`](../../scripts/connect.sh#L548)
