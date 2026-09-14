---
title: 'Warn that a self-terminated session does not resume'
type: 'feature'
created: '2026-09-13'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '6c317657f8fe89cf5a034c4b574c73819594950c'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `docs/sessions.md` documents recovery for a dropped link, a deliberate detach, `stop.sh`, and a host reboot, but not for the `claude` process inside `claude-<workspace>` exiting or crashing on its own — the one case where the tmux session dies with it, so the next `connect.sh` silently starts a brand-new conversation. This is retro item 2 (`epic-3-retro-2026-09-11.md`), already recorded in `deferred-work.md` (source_spec `spec-2-4-...`, line 141).

**Approach:** Add a new caveat section to `docs/sessions.md`, parallel in structure to the existing "Caveat: host reboot" section, naming the tmux-session-dies-with-the-process mechanism, pointing at `scripts/status.sh` as the pre-check that makes the empty case visible before reconnecting, and naming `claude --resume claude-<workspace>` as the recovery (consistent with AD-4 and the host-reboot flow). Verify `status.sh`'s existing per-session `<workspace> <attached|detached> <created>` / `no sessions` output already satisfies the "distinguishes no-session from running" requirement (it does — confirmed by existing `selftest_case_mixed_sessions`/`selftest_case_zero_sessions`); no `status.sh` code change is expected unless investigation finds a real gap.

## Boundaries & Constraints

**Always:** New doc section must not contradict or duplicate the existing "Caveat: host reboot" or "Reattach after a dropped link" sections — cross-reference them instead of restating. No new script, flag, or dependency (AD-8). `status.sh --check` and `doctor.sh --check` must still pass; shellcheck stays clean.

**Ask First:** If investigation finds `status.sh`'s current output does *not* clearly satisfy AC2 (e.g., a real ambiguity, not just a cosmetic preference), HALT and ask before changing `print_sessions()`'s output contract — it's depended on by existing selftests and doc cross-references.

**Never:** Do not touch `start-claude.sh`'s exec/launch pattern (the process-dies-kills-session behavior is inherent to it and out of scope — this story documents it, it doesn't change it). Do not edit any other deferred-work.md entry.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Self-terminated, then reconnect | `claude` inside `claude-<workspace>` exited/crashed on its own; tmux session is gone | `connect.sh` recreates `claude-<workspace>` fresh (via `start-claude.sh`'s `tmux new -A`) and launches a brand-new conversation | Documented, not scripted — same manual `claude --resume claude-<workspace>` recovery as host reboot |
| Pre-check via status.sh | Workspace's `claude-<workspace>` session does not exist (self-terminated or never started) | `status.sh` either omits it from a mixed list or prints `no sessions` — both already distinguish it from an `attached`/`detached` running session | N/A (read-only, no state file) |

</frozen-after-approval>

## Code Map

- `docs/sessions.md` -- add new `## Caveat: the claude process itself exits or crashes` section after the existing "Caveat: host reboot" section (currently L91-116); reuse its exact recovery wording (`start-claude.sh <workspace>` then `Ctrl-b c` then `claude --resume claude-<workspace>`) and reference `scripts/status.sh` (already documented in section 3, L67-69) as the pre-check. Update the `## Verification` section (L140-152) to record this addition.
- `scripts/status.sh` -- read-only verification target; `print_sessions()` (L96-117) and `selftest_case_mixed_sessions`/`selftest_case_zero_sessions` (L295-340) already cover the no-session-vs-running distinction this story's AC2 requires. No code change expected.
- `skills/implementation-artifacts/deferred-work.md` -- add an `addressed_by:` line to the entry at L141-143 pointing at this spec.

## Tasks & Acceptance

**Execution:**
- [x] `docs/sessions.md` -- add the self-terminated-process caveat section -- closes AC1, retro item 2
- [x] `docs/sessions.md` -- update `## Verification` to note the new section and that `status.sh`'s existing output/tests already satisfy AC2 -- keeps the doc's own verification trail accurate
- [x] `skills/implementation-artifacts/deferred-work.md` -- mark the L141-143 entry addressed -- closes AC3

**Acceptance Criteria:**
- Given `docs/sessions.md`, when reading the reattach flow, then it states that a self-exited/crashed `claude` process takes its tmux pane down with it, so the next `connect.sh` starts a brand-new conversation, and names `claude --resume claude-<workspace>` as the recovery, consistent with the host-reboot flow (AD-4).
- Given `scripts/status.sh`, when a workspace has no live session, then its output distinguishes that from a running one clearly enough to be visible before reconnecting, without a new dependency (AD-8) -- verified against existing behavior/tests, not a new code path unless investigation says otherwise.
- Given the change, then `status.sh --check` and `doctor.sh --check` still pass, shellcheck stays clean, and the deferred-work entry is marked addressed.

## Spec Change Log

## Design Notes

The host-reboot caveat (L91-116) is the template: same two-step recovery (`start-claude.sh` to recreate the session, then `claude --resume claude-<workspace>` in a second window since the first window is running `claude` directly with no shell left). The new section differs only in *why* the session is gone (the process died vs. the host restarted) and should say so explicitly, so a reader doesn't think this is a third, different mechanism.

## Verification

**Commands:**
- `scripts/status.sh --check` -- expected: PASS, unchanged
- `scripts/doctor.sh --check` -- expected: PASS, `other-script:status.sh` still PASS
- `shellcheck scripts/status.sh` -- expected: clean (no change expected, re-run to confirm)

**Manual checks (if no CLI):**
- Every cross-reference in the new `docs/sessions.md` section resolves to a real heading (the host-reboot caveat, section 3's `status.sh` mention).
- `deferred-work.md` L141-143 entry has an `addressed_by:` line pointing at this spec file.

## Suggested Review Order

**Self-terminated-session caveat**

- New section naming the failure mode and why the tmux session dies with the process.
  [`sessions.md:119`](../../docs/sessions.md#L119)

- Recovery reuses the host-reboot caveat's exact steps rather than a new mechanism.
  [`sessions.md:136`](../../docs/sessions.md#L136)

- `status.sh` named as the pre-reconnect check that makes the empty case visible.
  [`sessions.md:130`](../../docs/sessions.md#L130)

- Guide's own summary of contents updated so this scenario isn't missing from it.
  [`sessions.md:5`](../../docs/sessions.md#L5)

**Verification trail (peripheral)**

- Records that no `status.sh` code change was needed, only verified against existing tests.
  [`sessions.md:186`](../../docs/sessions.md#L186)

- Tracking entry closed: retro item 2 now points at this spec as its resolution.
  [`deferred-work.md:144`](deferred-work.md#L144)
