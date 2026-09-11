---
title: 'Start Claude Code in a persistent tmux session on the host'
type: 'feature'
created: '2026-09-11'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '5bf46d6fe7a3a1eb3453d07b59c495903f6725e1'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A host operator has no command that opens Claude Code for a workspace and keeps it running when the terminal goes away — without one, every session dies the moment a connection drops.

**Approach:** Add `scripts/start-claude.sh <workspace>`, which validates role/workspace/identity, then runs `tmux new -A -s claude-<workspace>` with a command that `cd`s into the workspace and launches `claude` in normal permission mode — idempotent attach-or-create, so re-running is always safe.

## Boundaries & Constraints

**Always:** Requires `NODE_ROLE=host|both` (resolved the same file→env-var precedence as `doctor.sh`) and `EUID != 0`; both violations exit 2 with one stderr line, before touching tmux. `<workspace>` must match `[a-z0-9-]+` and `$WORKSPACES_DIR/<workspace>` must already exist, else exit 2 with one stderr line and no side effects (never creates a workspace). On success, runs exactly `tmux new -A -s claude-<workspace> -- bash -lc 'cd "$WORKSPACES_DIR/<workspace>" && exec claude -n claude-<workspace> --permission-mode default'` (attach-or-create: `-A` attaches if `claude-<workspace>` already exists instead of starting a second Claude Code) and replaces the current process via `exec tmux ...` so the user lands directly in the session. Never passes `--dangerously-skip-permissions`, `bypassPermissions`, or `--add-dir` (AD-6). Exposes `--check`: a side-effect-free self-test (all state in a `mktemp -d` sandbox, PATH-stubbed `tmux`/`claude`, no real tmux server touched) exiting 0 on success, discoverable by `doctor.sh`'s existing `run_other_scripts_check` aggregator (requires the file be executable). `#!/usr/bin/env bash` + `set -euo pipefail`, bash 3.2 syntax only, shellcheck 0.11.0 clean, no `jq`/Python (AD-8). Output never contains tokens, keys, tailnet IPs, or node names.

**Ask First:** None expected.

**Never:** Do not create `status.sh`, `stop.sh`, `connect.sh`, or `enroll.sh` — later stories. Do not create the workspace directory if missing. Do not add a `--role` flag (reserved by `doctor.sh`, unused here).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fresh start | `NODE_ROLE=host`, workspace `demo` exists, no `claude-demo` session | creates `claude-demo`, cwd is workspace, lands in Claude Code | N/A |
| Re-run / reattach | `claude-demo` session already running | attaches, scrollback intact, no second Claude Code started | N/A |
| Bad workspace name | `<workspace>` empty or has chars outside `[a-z0-9-]` | exit 2, one stderr line, nothing created | N/A |
| Missing workspace dir | `$WORKSPACES_DIR/<workspace>` does not exist | exit 2, one stderr line, nothing created | N/A |
| Wrong role | `NODE_ROLE=client` | exit 2, one stderr line | N/A |
| Root | script runs as `EUID 0` | exit 2, one stderr line | N/A |
| Self-test | `start-claude.sh --check` | sandboxed run, exit 0, no real tmux/claude invoked | N/A |

</frozen-after-approval>

## Code Map

- `scripts/start-claude.sh` -- new; the launch script implementing role/EUID/workspace validation + `tmux new -A -s` attach-or-create + `--check` self-test.
- `scripts/doctor.sh:89` (`resolve_and_validate_role`) -- role-resolution pattern to mirror (file → `$NODE_ROLE` → default), including sourcing `config/local.env` via `CONFIG_FILE="${DOCTOR_CONFIG_FILE:-$SCRIPT_DIR/../config/local.env}"`; read-only, do not modify.
- `scripts/doctor.sh:40` (`die2`) and `:24` (`usage`) -- exit-2/one-stderr-line and `--help` conventions to mirror inline (AD-8: no shared shell library, so re-implement locally rather than sourcing `doctor.sh`).
- `scripts/doctor.sh:118` (`WORKSPACES_DIR="${WORKSPACES_DIR:-$HOME/workspaces}"`) and `:239` (`check_workspaces_dir`) -- the existing default/validation convention for `WORKSPACES_DIR` to reuse.
- `scripts/doctor.sh:665` (`run_other_scripts_check`) -- the aggregator this script's `--check` must satisfy: iterates `$SCRIPT_DIR/*.sh`, skips non-executable files (prints `SKIP`), else runs `"$script" --check` and requires exit 0. The new file must be committed executable (`git update-index --chmod=+x`, per story 1.2's precedent — this sandbox blocks `chmod`).
- `scripts/doctor.sh:686` (`run_self_test`) -- hermetic self-test pattern to mirror: `mktemp -d` sandbox, PATH-stubbed tool binaries, `trap ... EXIT` cleanup.
- `config/local.env.example` -- read-only; already documents `NODE_ROLE` and `WORKSPACES_DIR`, no change needed.

## Tasks & Acceptance

**Execution:**
- [x] `scripts/start-claude.sh` -- implement role (`host|both`) + EUID + workspace-name + workspace-existence validation, then `exec tmux new -A -s claude-<workspace> ...` launching `claude` in normal permission mode, plus `--check` self-test and `-h`/`--help` -- FR4, FR5, FR8, AD-1, AD-4, AD-6, AD-8

**Acceptance Criteria:**
- Given `NODE_ROLE=host|both` and an existing `$WORKSPACES_DIR/<workspace>`, when running `scripts/start-claude.sh <workspace>`, then it runs `tmux new -A -s claude-<workspace>` whose command `cd`s into the workspace and launches `claude -n claude-<workspace> --permission-mode default`, landing in Claude Code with the workspace as cwd.
- Given the tmux session `claude-<workspace>` already exists, when running the script again, then it attaches (scrollback intact) without starting a second Claude Code.
- Given `<workspace>` missing, invalid, or its directory absent, when running the script, then it exits 2 with one stderr line and creates nothing.
- Given `NODE_ROLE=client` or `EUID 0`, when running the script, then it exits 2 with one stderr line.
- Given the script source, then it never passes `--dangerously-skip-permissions`/`bypassPermissions`/`--add-dir`, exposes `--check`, and is shellcheck-clean bash 3.2.
- Given `doctor.sh --check` with `scripts/start-claude.sh` present and executable, then `run_other_scripts_check` reports `PASS other-script:start-claude.sh`.

## Spec Change Log

## Design Notes

Self-test sandbox mirrors `doctor.sh`'s: `mktemp -d`, a temp `bin/` prepended to `PATH` with stub `tmux`/`claude` executables (the stub `tmux` records its argv to a file instead of starting a real server; the stub `claude` just echoes and exits), and `HOME`/`WORKSPACES_DIR`/`DOCTOR_CONFIG_FILE`-equivalent overrides so no real tmux server or Claude process is ever touched. Assert on the recorded argv (session name, `-A` flag present, `cd` target, `claude` flags) rather than on any real terminal output, since `tmux new` without `-d` would otherwise attach to a TTY the self-test doesn't have.

Because the launch step replaces the shell (`exec tmux ...`), the self-test must invoke validation and command-construction as a function it can call without triggering `exec`, or run the real script in a stubbed-PATH subshell where the stubbed `tmux` exits immediately after recording argv (never attaching).

## Verification

**Commands:**
- `shellcheck scripts/start-claude.sh` -- expected: clean
- `scripts/start-claude.sh --check` -- expected: exit 0
- `scripts/doctor.sh --check` -- expected: still exit 0, now including `PASS other-script:start-claude.sh`
- Manual: `cp config/local.env.example config/local.env`, set `NODE_ROLE=host`, `mkdir -p "$WORKSPACES_DIR/demo"`, run `scripts/start-claude.sh demo` twice -- expected: first creates+attaches, second re-attaches without a second Claude Code process

## Suggested Review Order

**Entry point and launch**

- Dispatches to self-test, help, or the validate-then-launch happy path.
  [`start-claude.sh:478`](../../scripts/start-claude.sh#L478)

- Builds the tmux/claude invocation; `$dir`/`$session` are `printf %q`-escaped before splicing into the inner `bash -lc` string, closing a command-injection surface a review flagged in the first pass.
  [`start-claude.sh:121`](../../scripts/start-claude.sh#L121)

**Validation (role, workspace, identity)**

- Role resolution mirrors `doctor.sh`'s file-then-env precedence; a stray `exit` inside a malformed `config/local.env` is now suppressed from stderr so the script's own one-line diagnostic is what actually surfaces.
  [`start-claude.sh:84`](../../scripts/start-claude.sh#L84)

- Workspace-name regex now runs under a locale-pinned `LC_ALL=C` so bracket-range matching can't vary by the operator's locale.
  [`start-claude.sh:69`](../../scripts/start-claude.sh#L69)

- Workspace-existence check; script never creates the directory itself.
  [`start-claude.sh:109`](../../scripts/start-claude.sh#L109)

- Root guard; the test-only EUID override now requires a second self-test marker (`START_CLAUDE_SELFTEST`) to be honored, so it's inert outside `--check`.
  [`start-claude.sh:59`](../../scripts/start-claude.sh#L59)

**Self-test harness**

- Orchestrates all 11 hermetic cases (7 original + 4 added during review: `both`-role, broken-config, `--help`, wrong-arg-count) against a `mktemp -d` sandbox with PATH-stubbed `tmux`/`claude`.
  [`start-claude.sh:440`](../../scripts/start-claude.sh#L440)

- Representative case: asserts the exact tmux argv shape (session name, `-A`, cwd, forbidden-flag absence) and actually executes the constructed command line against a stub `claude`.
  [`start-claude.sh:204`](../../scripts/start-claude.sh#L204)

- New coverage closing a verification-gap finding: the previously-untested `NODE_ROLE=both` acceptance path.
  [`start-claude.sh:366`](../../scripts/start-claude.sh#L366)

- New coverage closing a verification-gap finding: the previously-untested malformed-`config/local.env` rejection path.
  [`start-claude.sh:385`](../../scripts/start-claude.sh#L385)
