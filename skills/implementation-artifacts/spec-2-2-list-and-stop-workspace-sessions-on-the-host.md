---
title: 'List and stop workspace sessions on the host'
type: 'feature'
created: '2026-09-11'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: 'd9b9401df2fd3bdfd6fdf0ab13f41729327fb6e5'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A host operator has no way to see which `claude-<workspace>` tmux sessions are running, or to stop exactly one without risking the rest.

**Approach:** Add `scripts/status.sh`, which lists every `claude-<workspace>` tmux session (workspace name, attached/detached, creation time) from live tmux state, and `scripts/stop.sh <workspace>`, which kills exactly that one named session.

## Boundaries & Constraints

**Always:** Both scripts require `NODE_ROLE=host|both` (same file→env-var precedence as `doctor.sh`/`start-claude.sh`); `NODE_ROLE=client` exits 2 with one stderr line before touching tmux (AD-1). `status.sh` takes no args, lists sessions via `tmux list-sessions -F '#{session_name}|#{session_attached}|#{t:session_created}'`, filters to names matching `claude-*`, prints one line per match as `<workspace> <attached|detached> <created>` (attached when the client count is `>0`), and prints exactly `no sessions` with exit 0 when there are none or tmux has no server running. `stop.sh <workspace>` validates `<workspace>` against `[a-z0-9-]+` (reuse `start-claude.sh`'s regex), checks `tmux has-session -t claude-<workspace>`, and on a match runs exactly `tmux kill-session -t claude-<workspace>` and exits 0; it never passes a wildcard or calls `kill-server` (AD-4). No session named `claude-<workspace>` exits 2 with one stderr line, no tmux mutation. Both scripts expose `--check` (side-effect-free self-test, `mktemp -d` sandbox, PATH-stubbed `tmux`, no real tmux server touched), discoverable by `doctor.sh`'s `run_other_scripts_check`. `#!/usr/bin/env bash` + `set -euo pipefail`, bash 3.2 syntax only, shellcheck 0.11.0 clean, no `jq`/Python (AD-8). Output never contains tokens, keys, tailnet IPs, or node names.

**Ask First:** None expected.

**Never:** Do not create `connect.sh` or `enroll.sh` (later stories). Do not persist a state file — session state is derived from `tmux list-sessions` only. Do not add a root/EUID check (not required by this story's AC, unlike `start-claude.sh`).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| `status.sh`, zero sessions | no tmux server, or none match `claude-*` | prints `no sessions`, exit 0 | N/A |
| `status.sh`, mixed sessions | `claude-demo` (attached), `claude-idle` (detached), `other` (non-claude) | two lines, one per `claude-*` session; `other` excluded | N/A |
| `stop.sh demo`, running | `claude-demo` session exists | runs `tmux kill-session -t claude-demo`, exits 0; other `claude-*` sessions untouched | N/A |
| `stop.sh ghost`, absent | no `claude-ghost` session | exit 2, one stderr line, no tmux mutation | N/A |
| either script, `NODE_ROLE=client` | wrong role | exit 2, one stderr line, before any tmux call | N/A |
| `stop.sh` bad name | `<workspace>` outside `[a-z0-9-]+` | exit 2, one stderr line, no tmux mutation | N/A |

</frozen-after-approval>

## Code Map

- `scripts/status.sh` -- new; lists `claude-*` tmux sessions from live state.
- `scripts/stop.sh` -- new; kills exactly one named `claude-<workspace>` session.
- `scripts/start-claude.sh:50` (`die2`), `:28` (`usage`) -- exit-2/one-stderr-line and `--help` conventions to mirror inline (AD-8: no shared library).
- `scripts/start-claude.sh:69` (`validate_workspace_name`, `LC_ALL=C` regex) -- reuse pattern verbatim for `stop.sh`.
- `scripts/start-claude.sh:84` (`resolve_and_validate_role`) -- reuse the `host|both` role-gating pattern (this story needs no `WORKSPACES_DIR`).
- `scripts/start-claude.sh:135` (`write_stub_tools`), `:157`-`:202` (assert helpers), `:440` (`run_self_test`) -- self-test harness pattern to mirror: `mktemp -d` sandbox, PATH-stubbed `tmux`, `trap ... EXIT` cleanup, `env -i` isolated cases.
- `scripts/doctor.sh:665` (`run_other_scripts_check`) -- the `--check` aggregator both new scripts must satisfy (requires the file be committed executable via `git update-index --chmod=+x`, per story 1.2/2.1 precedent).

## Tasks & Acceptance

**Execution:**
- [x] `scripts/status.sh` -- implement role gate + `tmux list-sessions` parsing/filtering + `no sessions` fallback + `--check` self-test + `-h`/`--help` -- FR7, FR8, AD-1, AD-8
- [x] `scripts/stop.sh` -- implement role gate + workspace-name validation + `has-session`/`kill-session` + `--check` self-test + `-h`/`--help` -- FR7, AD-1, AD-4, AD-8

**Acceptance Criteria:**
- Given zero or more `claude-*` tmux sessions, when running `scripts/status.sh`, then it prints one line per `claude-<workspace>` session (workspace name, attached/detached, creation time) derived from live tmux state only, or `no sessions` with exit 0 when none exist.
- Given a running `claude-<workspace>` session, when running `scripts/stop.sh <workspace>`, then it kills only that session (no wildcard, no `kill-server`) and exits 0; other `claude-*` sessions are untouched.
- Given no session named `claude-<workspace>`, when running `stop.sh <workspace>`, then it exits 2 with one stderr line.
- Given `NODE_ROLE=client`, when running either script, then it exits 2 with one stderr line.
- Given `doctor.sh --check` with both scripts present and executable, then `run_other_scripts_check` reports `PASS other-script:status.sh` and `PASS other-script:stop.sh`.

## Spec Change Log

## Design Notes

`status.sh` uses tmux's own `#{t:session_created}` strftime format spec to render creation time, avoiding a shelled-out `date` call whose GNU/BSD flag syntax diverges (no `jq`/Python, AD-8). Self-tests stub `tmux list-sessions`/`has-session`/`kill-session` by recording invoked subcommands and returning canned pipe-delimited lines or fixed exit codes via env vars, mirroring `start-claude.sh`'s argv-recording stub -- no real tmux server is ever touched.

## Verification

**Commands:**
- `shellcheck scripts/status.sh scripts/stop.sh` -- expected: clean
- `scripts/status.sh --check` -- expected: exit 0
- `scripts/stop.sh --check` -- expected: exit 0
- `scripts/doctor.sh --check` -- expected: still exit 0, now including `PASS other-script:status.sh` and `PASS other-script:stop.sh`
- Manual: `NODE_ROLE=host scripts/start-claude.sh demo` (in a separate detached call, e.g. `tmux new -d -s claude-demo`), then `scripts/status.sh` shows it detached; `scripts/stop.sh demo` kills it; `scripts/status.sh` shows `no sessions`

## Suggested Review Order

**Stopping exactly one session (AD-4)**

- Entry point: dispatches to self-test, help, or validate-then-stop.
  [`stop.sh:459`](../../scripts/stop.sh#L459)

- The exact-match `=` sigil forces tmux to reject prefix matches, closing a review-confirmed cross-session-kill gap (`claude-demo` could otherwise match `claude-demo2`); the `kill-session` call is now guarded the same way as `has-session`, so a race or socket error exits 2 with one line instead of leaking tmux's raw error.
  [`stop.sh:99`](../../scripts/stop.sh#L99)

- Proves the whole recorded tmux argv is exactly `has-session -t =claude-<ws>` then `kill-session -t =claude-<ws>` -- nothing else, no wildcard, no `kill-server`.
  [`stop.sh:200`](../../scripts/stop.sh#L200)

- New case closing the unguarded-kill gap: `has-session` succeeds but `kill-session` fails.
  [`stop.sh:230`](../../scripts/stop.sh#L230)

**Listing sessions from live tmux state (FR7/FR8)**

- Parses `tmux list-sessions`' `name|attached|created` lines, filters to `claude-*`, and falls back to `no sessions` when tmux has no server or returns nothing.
  [`status.sh:84`](../../scripts/status.sh#L84)

- Uses tmux's own `#{t:session_created}` strftime spec instead of a separately shelled-out `date` call, sidestepping GNU/BSD flag divergence.
  [`status.sh:87`](../../scripts/status.sh#L87)

- Strengthened from a substring check to an exact full-stdout match, so a dropped/reordered `created` field (verification-gap finding, reproduced by the reviewer) now fails `--check` instead of passing silently.
  [`status.sh:331`](../../scripts/status.sh#L331)

**Shared conventions (mirrored from `start-claude.sh`, AD-1/AD-8)**

- Role gate: `config/local.env` wins over `$NODE_ROLE`, `host|both` only; identical shape in both new scripts.
  [`status.sh:54`](../../scripts/status.sh#L54)
  [`stop.sh:72`](../../scripts/stop.sh#L72)

- `--check` self-test harness: `mktemp -d` sandbox, PATH-stubbed `tmux` recording argv, `trap ... EXIT` cleanup -- no real tmux server touched by either script's self-test.
  [`stop.sh:421`](../../scripts/stop.sh#L421)
  [`status.sh:376`](../../scripts/status.sh#L376)
