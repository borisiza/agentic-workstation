---
title: 'Survive a dropped link and resume within a minute, in both directions'
type: 'feature'
created: '2026-09-11'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '72505c735d2c061aaa3a45a2d240d3c081a2201b'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Stories 2.1-2.3 already built the persistence and no-collision mechanics (`start-claude.sh`'s `tmux new -A -s claude-<workspace>`, `stop.sh`'s exact-target kill, `connect.sh`'s chained exec), but nothing documents the reconnect/recovery flow for the owner, and the two-node, both-directions guarantee (AD-4, NFR2) has never been verified end-to-end.

**Approach:** Add no new scripts. Ship `config/tmux.conf.example` (large `history-limit`, mouse support, optional install) and `docs/sessions.md` (reattach flow, detach key, host-reboot recovery via `claude --resume claude-<workspace>`, the `tailscaled`-restart shim, transcript location). Execute the M1 protocol (A→B start, kill link, reconnect under 60s, intact; then B→A while A→B still runs) and record pass/fail plus measured reconnect time in story notes, no node names (AD-7).

## Boundaries & Constraints

**Always:** No script changes — `scripts/start-claude.sh`, `status.sh`, `stop.sh`, `connect.sh` are read-only reuse. `docs/sessions.md` matches the established doc style (`docs/node-*.md`: H1 title, numbered/`##` sections, `## Caveat:` for edge cases, `## Verification`). `config/tmux.conf.example` matches `config/ssh_config.example`'s header-block + "Usage" style (optional template, not sourced by any script). No node names, tailnet IPs, or tokens anywhere (AD-7).

**Ask First:** none.

**Never:** No automated recovery for a host reboot (documented manual step only, per epic-2-context's own scope boundary). No new script, no doctor.sh check (doctor.sh only auto-discovers `scripts/*.sh`; docs/config are out of its glob).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Reconnect after drop | Session `claude-<workspace>` running on host; link dropped then restored | Re-running `connect.sh <node> <workspace>` reattaches with scrollback + context intact, <60s | N/A |
| Both-directions coexistence | A→B session running; B→A `start-claude.sh` invoked on A from B | Two independent tmux sessions, one per host, neither affected by the other | N/A |
| Host reboot | tmux server gone | Documented manual step: `start-claude.sh <workspace>` then `claude --resume claude-<workspace>` inside the new session | N/A (not automated, by design) |

</frozen-after-approval>

## Code Map

- `config/tmux.conf.example` -- new; mirror `config/ssh_config.example:1-9`'s header-block + "Usage once configured" style.
- `docs/sessions.md` -- new; mirror `docs/node-client.md`/`docs/node-macos.md` structure (H1, numbered sections, `## Caveat:`, `## Verification`).
- `scripts/start-claude.sh:12-14,34-38,121-129` -- read-only; cite the `tmux new -A -s claude-<workspace>` attach-or-create contract verbatim, do not reimplement.
- `docs/node-macos.md:227-284` / `docs/node-linux.md:206-245` -- read-only; existing `tailscale serve --tcp 2222 22` shim wording under "## Caveat: tailscaled restart and manual recovery" -- `sessions.md` links/summarizes, does not re-litigate.
- `skills/planning-artifacts/architecture/.../ARCHITECTURE-SPINE.md` AD-4 (persistence contract, `claude --resume claude-<workspace>` phrasing) and AD-7 (no node names, transcripts in `~/.claude/`) -- source of truth for exact phrasing used in `sessions.md`.
- `skills/implementation-artifacts/spec-2-3-...md` -- prior story continuity (Code Map/self-test conventions), no direct reuse needed since this story adds no script.

## Tasks & Acceptance

**Execution:**
- [x] `config/tmux.conf.example` -- add `set -g history-limit <large>` + `set -g mouse on` + header/Usage comment block -- NFR2
- [x] `docs/sessions.md` -- write reattach flow, detach key, reboot-recovery step, tailscaled-restart shim link, transcript-location note, `config/tmux.conf.example` install instructions -- FR6, AD-4, AD-7
- [ ] Story notes (this spec's Verification section, filled at review time) -- record M1 protocol outcome (pass/fail, measured reconnect time, no node names) -- NFR2, M1 -- **outstanding human action**: this automated build environment has no second tailnet node, so the M1 protocol could not be executed here (see Verification below); a human must run it on two real nodes before this story is promoted to done.

**Acceptance Criteria:**
- Given a session started with `connect.sh` from node A to node B, when the link is killed and `connect.sh <node> <workspace>` is re-run after the network is back, then the same session is reattached with prior scrollback and conversation context in under 60 seconds.
- Given the same setup B→A while A→B is still running, when `claude-<workspace>` is started on A from B, then both sessions coexist (one per host tmux server) and neither is affected by the other.
- Given `config/tmux.conf.example`, then it sets a large `history-limit` and mouse support, with docs explaining optional install as `~/.tmux.conf`.
- Given `docs/sessions.md`, then it documents the reattach flow, detach key, reboot recovery, the tailscaled-restart shim, and that transcripts live in `~/.claude/` on the host.
- Given the M1 protocol executed on two real nodes, then the outcome (pass, measured reconnect time) is recorded in story notes without node names.

## Spec Change Log

## Design Notes

This story's own Verification section doubles as the "story notes" the AC asks for -- the M1 protocol result is recorded there rather than in a separate file, since no other story in this epic created a standalone notes file and `docs/sessions.md` itself must stay reader-facing (no test-log content). If the M1 protocol cannot be executed against two real tailnet nodes inside the automated build environment, that limitation is stated explicitly in Verification rather than fabricating a result -- see step-03 handoff.

## Verification

**Commands:**
- `shellcheck` -- N/A, no script changes.
- `gitleaks git --pre-commit --staged` -- ran against the two new files (`config/tmux.conf.example`, `docs/sessions.md`) staged: **clean, 0 leaks found** (`gitleaks` 8.30.1, "no leaks found").

**Manual checks (if no CLI):**
- `docs/sessions.md` cross-references resolve -- confirmed: `## Caveat: tailscaled restart and manual recovery` exists verbatim at `docs/node-macos.md:227` and `docs/node-linux.md:206`, matching the anchors `sessions.md` links to.
- `config/tmux.conf.example` is valid tmux syntax -- the sandboxed build environment executing this spec blocks direct `tmux` invocations (including `tmux -V`/`tmux -f ... -C kill-server`) pending human approval, so the dry-run check from the Code Map could not be executed here. Verified instead by manual read: the file contains exactly two directives, `set -g history-limit 50000` and `set -g mouse on`, both standard `set [-g] option value` tmux.conf syntax with no typos or unsupported flags. A human with an unrestricted shell should still run `tmux -f config/tmux.conf.example -C kill-server` (or just `cp` it to `~/.tmux.conf` and start a session) to confirm live, before relying on it.
- M1 protocol (A→B start, kill link, reconnect, intact; then B→A) -- **not executed**. This automated build environment has exactly one machine and no second tailnet node to pair it with, so the two-node reconnect/coexistence protocol described in the Intent and AC could not be run here. No result is fabricated. This is an **outstanding human action**: before this story is promoted to done, a human must run the M1 protocol on two real tailnet nodes (A→B start a session, kill the link, re-run `connect.sh <node> <workspace>` after the network is back and confirm scrollback/context intact in under 60s and record the measured time; then start `claude-<workspace>` on A from B while A→B is still running and confirm both sessions coexist independently) and record pass/fail plus the measured reconnect time in this section, with no node names, before flipping this task's checkbox and this spec's `status` to `done`.

  **M1 result:** NOT YET RUN -- fill in after executing on two real nodes: `A→B reconnect: <pass/fail>, <Ns>` / `B→A coexistence: <pass/fail>`.

## Suggested Review Order

**Reattach and reboot-recovery mechanics**

- Entry point: reattach flow, cites `start-claude.sh`'s `-A` attach-or-create contract and the stop.sh distinction added in review.
  [`sessions.md:21`](../../docs/sessions.md#L21)

- Host-reboot recovery, corrected in review: `start-claude.sh` execs `claude` directly with no shell left, so resuming needs a second tmux window (`Ctrl-b c`) before `claude --resume claude-<workspace>` — the highest-risk fix in this diff.
  [`sessions.md:91`](../../docs/sessions.md#L91)

**Both-directions coexistence and the M1 gap**

- States the no-collision guarantee (AD-4) and points to `status.sh` (added in review) as the way to observe it live.
  [`sessions.md:58`](../../docs/sessions.md#L58)

- Honest record that the M1 two-node protocol itself was not executed in this build environment, with an explicit outstanding-human-action note and a fill-in template.
  [`spec-2-4-survive-a-dropped-link-and-resume-within-a-minute-in-both-di.md:75`](spec-2-4-survive-a-dropped-link-and-resume-within-a-minute-in-both-di.md#L75)

**tailscaled-restart caveat**

- Links out to the three host guides' existing shim documentation instead of duplicating it; WSL link added in review alongside macOS/Linux.
  [`sessions.md:118`](../../docs/sessions.md#L118)

**Peripherals**

- New optional tmux config: global `history-limit`/`mouse` settings, with the global-scope and mouse-mode-selection caveats added in review.
  [`tmux.conf.example:13`](../../config/tmux.conf.example#L13)

- `sprint-status.yaml` flip to `in-progress` (epic-2 already in-progress, no lift needed).
  [`sprint-status.yaml:51`](../../skills/implementation-artifacts/sprint-status.yaml#L51)

