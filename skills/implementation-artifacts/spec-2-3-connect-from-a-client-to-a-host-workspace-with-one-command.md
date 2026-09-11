---
token_cost: {input: 29859, output: 9191, cache_read: 4156756, total: 4195806}
final_revision: 'c0c1cafd09269eed2027b2980453f53bfd025183'
title: 'Connect from a client to a host workspace with one command'
type: 'feature'
created: '2026-09-11'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: 'f4f8ee1ea76f253ecf024db9cc989138b8f61b26'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A client node has no single command to reach a chosen workspace on a host and land inside its persistent Claude Code session; discovering which hosts are even reachable requires manually reading `tailscale status`.

**Approach:** Add `scripts/connect.sh <node> <workspace>`, which chains `tailscale ssh` straight into the host's `start-claude.sh` by absolute path, and a no-arg mode that lists currently-online tailnet peers parsed live from `tailscale status` text (never persisted). Ship `config/ssh_config.example` as an optional plain-`ssh` template.

## Boundaries & Constraints

**Always:** Requires `NODE_ROLE=client|both` (same config/local.env -> $NODE_ROLE precedence as the other scripts); `NODE_ROLE=host` exits 2 with one stderr line before any tailscale call (AD-1). With exactly two args `<node> <workspace>`: validate `<workspace>` against `[a-z0-9-]+` (reuse `start-claude.sh`'s `LC_ALL=C` regex), resolve `<user>` from `SSH_USER` in `config/local.env` (default: current login user via `${LOGNAME:-$(id -un)}`), reject `SSH_USER=root` (exit 2, one stderr line, AD-6), then `exec tailscale ssh -t <user>@<node> -- "$HOME/agentic-workstation/scripts/start-claude.sh" <workspace>` -- absolute path, since the remote non-interactive shell never sources a login profile. Re-running the same command reattaches (delegated entirely to `start-claude.sh`'s own idempotent attach-or-create; `connect.sh` adds no session-existence logic of its own). With zero args: parse `tailscale status` plain-text output (no `jq`), skip the first line (self), print one hostname per line for peers whose line does not end in `offline` (case-insensitive), exit 0 even when the list is empty; never write this list to any file. Exposes `--check` (side-effect-free self-test, PATH-stubbed `tailscale`, no real network/ssh/tailscale call) and `-h`/`--help`, discoverable by `doctor.sh`'s `run_other_scripts_check` (no `doctor.sh` edit needed -- it globs `scripts/*.sh`). `#!/usr/bin/env bash` + `set -euo pipefail`, bash 3.2 syntax only, shellcheck 0.11.0 clean, no `jq`/Python (AD-8). Output never contains tokens, keys, tailnet IPs, or node names beyond the hostnames `tailscale status` itself already prints in discovery mode.

**Ask First:** None expected.

**Never:** Do not create `enroll.sh` or touch `doctor.sh`/`start-claude.sh`/`status.sh`/`stop.sh`. Do not persist any host list to a file (AD-2). Do not add reconnect/retry logic (Story 2.4's concern). Do not implement the OpenSSH `--fallback` flag (Epic 3).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Connect, fresh or existing session | `connect.sh host1 demo`, `NODE_ROLE=client` | execs `tailscale ssh -t <user>@host1 -- "$HOME/agentic-workstation/scripts/start-claude.sh" demo` | N/A |
| Discovery, mixed peers | `connect.sh`, `tailscale status` lists self + 2 online + 1 offline | prints the 2 online peer hostnames, one per line, exit 0 | N/A |
| Discovery, no peers online | `connect.sh`, only self in `tailscale status` | prints nothing, exit 0 | N/A |
| Wrong role | `NODE_ROLE=host` | exit 2, one stderr line, before any tailscale call | N/A |
| Bad workspace name | `connect.sh host1 "Bad Name!"` | exit 2, one stderr line, no tailscale call | N/A |
| Root SSH user | `SSH_USER=root`, `connect.sh host1 demo` | exit 2, one stderr line, no tailscale call | N/A |
| Missing workspace arg | `connect.sh host1` (one arg) | exit 2, one stderr line | N/A |

</frozen-after-approval>

## Code Map

- `scripts/connect.sh` -- new; two-arg connect (exec `tailscale ssh` into `start-claude.sh`) + zero-arg peer discovery.
- `config/ssh_config.example` -- new; `Host <node>` template with `ServerAliveInterval 15`/`ServerAliveCountMax 3` (NFR2), documented as optional for plain-`ssh` users.
- `config/local.env.example:11` -- `SSH_USER` already declared; its comment says "host-only" but this story reads it client-side too -- correct the comment to reflect both uses.
- `scripts/start-claude.sh:22-24` (`SCRIPT_DIR`/`SCRIPT_PATH`/`CONFIG_FILE`), `:28` (`usage`), `:50` (`die2`), `:69` (`validate_workspace_name`, `LC_ALL=C`) -- reuse verbatim.
- `scripts/start-claude.sh:84` (`resolve_and_validate_role`) -- mirror the config-wins-over-env pattern, adapted to require `client|both` (inverse of `start-claude.sh`'s `host|both`).
- `scripts/start-claude.sh:135-202,440` (`write_stub_tools`, assert helpers, `run_self_test`) -- self-test harness pattern: `mktemp -d` sandbox, PATH-stubbed `tailscale` recording argv or emitting canned `status` text, `trap ... EXIT` cleanup.
- `scripts/doctor.sh:155-163` (`check_tailnet_membership`) -- reuse the backend-down first-line regex (`stopped|logged out|needs login|not running`) so discovery mode fails cleanly (exit 2) if the daemon itself isn't running, instead of misreporting "no peers".
- `scripts/doctor.sh:665` (`run_other_scripts_check`) -- auto-discovers `connect.sh` once committed executable; no edit needed.

## Tasks & Acceptance

**Execution:**
- [x] `scripts/connect.sh` -- implement role gate + two-arg connect (exec into `tailscale ssh`) + zero-arg discovery + `--check` self-test + `-h`/`--help` -- FR4, FR7, FR10, AD-1, AD-2, AD-6, AD-8
- [x] `config/ssh_config.example` -- add `Host <node>` template block -- NFR2
- [x] `config/local.env.example` -- fix `SSH_USER` comment to note it's read by both `start-claude.sh`'s host account and `connect.sh`'s client-side target user

**Acceptance Criteria:**
- Given `NODE_ROLE=client|both` and an enrolled host `<node>`, when running `connect.sh <node> <workspace>`, then it execs `tailscale ssh -t <user>@<node> -- "$HOME/agentic-workstation/scripts/start-claude.sh" <workspace>` with `<user>` from `SSH_USER` (default: current login user).
- Given `connect.sh` run with no arguments, then it lists online tailnet peers parsed from live `tailscale status` text only, exits 0, and persists nothing.
- Given `SSH_USER=root`, a missing `<workspace>` argument, or `NODE_ROLE=host`, when running `connect.sh`, then it exits 2 with one stderr line.
- Given `doctor.sh --check` with `connect.sh` present and executable, then `run_other_scripts_check` reports `PASS other-script:connect.sh`.

## Spec Change Log

## Design Notes

Discovery mode parses each `tailscale status` line with plain `read -r` word-splitting (no `awk`/`jq`, consistent with the rest of the repo's `cut`/`sed` toolkit): skip line 1 (self), skip any line whose last whitespace-separated field case-insensitively equals `offline`, print field 2 (hostname). The self-test stubs `tailscale status` to emit fixed canned text (self + online peer + offline peer) and stubs `tailscale ssh` to record its argv, mirroring `start-claude.sh`'s `write_stub_tools`/argv-recording approach -- no real network or tailscale call is ever made.

## Verification

**Commands:**
- `shellcheck scripts/connect.sh` -- expected: clean
- `scripts/connect.sh --check` -- expected: exit 0
- `scripts/doctor.sh --check` -- expected: still exit 0, now including `PASS other-script:connect.sh`
- Manual: on a client with `NODE_ROLE=client` and an enrolled host, `scripts/connect.sh` (no args) lists that host; `scripts/connect.sh <host> demo` lands in Claude Code; re-running reattaches with scrollback intact.

## Suggested Review Order

**Chaining into the host's start-claude.sh (FR4/FR7)**

- Entry point: dispatches to self-test, help, role gate, then zero-arg discovery vs. two-arg connect.
  [`connect.sh:649`](../../scripts/connect.sh#L649)

- Builds the `tailscale ssh` exec line; `$HOME/...` is deliberately single-quoted so the *remote* shell expands it, since `SSH_USER`'s home directory can differ from the local user's.
  [`connect.sh:123`](../../scripts/connect.sh#L123)

- Refuses an empty `<node>` before any tailscale call, mirroring `validate_workspace_name`'s empty-string guard added during review.
  [`connect.sh:125`](../../scripts/connect.sh#L125)

- Resolves `SSH_USER` (default: current login user) and refuses `root`, before the exec is ever built.
  [`connect.sh:109`](../../scripts/connect.sh#L109)

**Role gating (AD-1) and its self-test coverage**

- `client|both` only -- the inverse of `start-claude.sh`'s `host|both` -- config/local.env wins over `$NODE_ROLE`.
  [`connect.sh:83`](../../scripts/connect.sh#L83)

- Review-added case proving the role gate also blocks the zero-arg discovery path, not just two-arg connect.
  [`connect.sh:457`](../../scripts/connect.sh#L457)

- Review-added case proving a `config/local.env` that fails to source exits 2 before role resolution, closing a parity gap with the three sibling scripts.
  [`connect.sh:497`](../../scripts/connect.sh#L497)

**Discovery mode: parsing live `tailscale status` text (FR10/AD-2)**

- Skips line 1 (self) and any line ending in `offline`, printing only the hostname field; globbing is disabled around the intentional word-split so a stray `*`/`?`/`[` in a status line can't expand against local filenames.
  [`connect.sh:148`](../../scripts/connect.sh#L148)

- Backend-down detection reuses `doctor.sh`'s own first-line regex so a stopped/logged-out daemon fails cleanly instead of misreporting "no peers."
  [`connect.sh:153`](../../scripts/connect.sh#L153)

**Verification: proving the exec argv, not just its parts**

- Review-added helper asserting the recorded `tailscale ssh` argv matches an exact ordered sequence, closing a gap where independent substring checks would miss a reordered/broken invocation.
  [`connect.sh:298`](../../scripts/connect.sh#L298)

- The `--check` self-test itself: sandboxed via `env -i` and a PATH-stubbed `tailscale` recording argv/emitting canned `status` text -- no real network or ssh call.
  [`connect.sh:607`](../../scripts/connect.sh#L607)

**Peripherals**

- `SSH_USER`'s comment corrected to describe both its host-side and client-side (`connect.sh`) uses.
  [`local.env.example:10`](../../config/local.env.example#L10)

- New optional plain-`ssh` template, documented as not read by any script.
  [`ssh_config.example:10`](../../config/ssh_config.example#L10)
