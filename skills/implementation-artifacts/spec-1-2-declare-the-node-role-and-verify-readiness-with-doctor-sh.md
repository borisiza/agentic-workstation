---
title: 'Declare the node role and verify readiness with doctor.sh'
type: 'feature'
created: '2026-09-11'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '70704f01c62b7802b4473cc2d5b32e2bb2458d78'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A node has no way to declare its role or verify it is actually ready to join the mesh — nothing checks required tools, tailnet membership, `~/.ssh` permissions, or the per-platform contract before the owner tries `connect.sh`/`enroll.sh`, so failures surface late in the wrong script.

**Approach:** Add the committed `config/local.env.example` template and `scripts/doctor.sh`, which resolves `NODE_ROLE` (file → env var → flag precedence), validates it, then runs one `PASS|FAIL|SKIP` check per requirement — common checks always, host-only checks gated by role — and supports `--check` self-testing plus aggregation of any other `scripts/*.sh --check`.

## Boundaries & Constraints

**Always:** Role resolves in this order: `config/local.env` (if present, wins) → `NODE_ROLE` env var → a future `--role` flag hook (not otherwise used by this story). Missing config or a role outside `host|client|both` exits 2 with exactly one stderr line naming the fix. Common checks (any valid role): `tailscale` installed (≥1.102) and tailnet membership (backend `Running`), `tmux`, `claude`, `git` present, `~/.ssh` mode `0700`, every `~/.ssh/id_*` private key mode `0600`. `host|both` adds: Tailscale SSH advertised, `$WORKSPACES_DIR` exists, platform contract (macOS: Homebrew `tailscaled` is the active backend, not the GUI app; WSL: `systemd` is PID 1) — `client` SKIPs these. Exit 0 only when no check is `FAIL`. Output never contains tokens, keys, tailnet IPs (`100.x`, `fd7a:`), or node names. `doctor.sh --check` is a side-effect-free self-test (all state in a `mktemp -d` sandbox, PATH-stubbed tool binaries, cleaned up on exit) exiting 0 on success; it also runs `--check` for every other `scripts/*.sh` present and aggregates (absent scripts are skipped, not failed). `#!/usr/bin/env bash` + `set -euo pipefail`, bash 3.2 syntax only (no associative arrays, `${var,,}`, `mapfile`), shellcheck 0.11.0 clean, no `jq`/Python (AD-8).

**Ask First:** None expected. If the macOS backend or WSL PID-1 check cannot be written in portable bash, ask before adding a non-bash dependency.

**Never:** Do not create `connect.sh`, `enroll.sh`, `start-claude.sh`, `status.sh`, or `stop.sh` — later stories. Do not hardcode a real tailnet IP, hostname, or key value anywhere, including test fixtures.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Missing config | no `config/local.env` | exit 2, one stderr line naming the fix | N/A |
| Invalid role | `NODE_ROLE=bogus` | exit 2, one stderr line naming the fix | N/A |
| Valid client role | `NODE_ROLE=client`, tools present, `~/.ssh` perms correct | one PASS line per common check; host checks show SKIP; exit 0 | N/A |
| Valid host role, bad ssh perms | `NODE_ROLE=host`, `~/.ssh` mode `0755` | that check FAILs with fix hint; other checks still run; exit 1 | non-zero exit, no crash |
| Self-test | `doctor.sh --check` | sandboxed run, exit 0, no writes outside `mktemp -d` | N/A |
| Aggregation | `doctor.sh --check`, no other `scripts/*.sh` yet | doctor's own self-test result only, absent scripts skipped | N/A |

</frozen-after-approval>

## Code Map

- `config/local.env.example` -- new, committed template: `NODE_ROLE=`, `WORKSPACES_DIR=$HOME/workspaces`, `FALLBACK_SSHD=0`, `SSH_USER=`, one comment line per var.
- `scripts/doctor.sh` -- new, the readiness script implementing role resolution + all checks above.
- `scripts/.gitkeep`, `config/.gitkeep` -- delete; both dirs are no longer empty once the two files above land.
- `.github/workflows/hygiene.yml` -- no change needed; its `scripts/*.sh` shellcheck glob already picks up `doctor.sh`.
- `.gitignore` -- no change needed; `config/local.env` is already ignored (story 1.1).

## Tasks & Acceptance

**Execution:**
- [x] `config/local.env.example` -- create with the four documented vars and defaults -- FR17 committed template
- [x] `scripts/doctor.sh` -- implement role resolution/validation, common + host-gated PASS/FAIL/SKIP checks, redacted output, `--check` self-test with `scripts/*.sh --check` aggregation -- FR15, FR17, FR9, AD-1, AD-5, AD-8
- [x] `scripts/.gitkeep`, `config/.gitkeep` -- delete now that the dirs hold real files -- housekeeping

**Acceptance Criteria:**
- Given `config/local.env.example` copied to `config/local.env` with `NODE_ROLE=host`, when `doctor.sh` runs, then it reads the role per the file→env→flag precedence.
- Given `config/local.env` missing or an invalid `NODE_ROLE`, when `doctor.sh` runs, then it exits 2 with exactly one stderr line naming the fix.
- Given any valid role, when `doctor.sh` runs, then it prints one `PASS|FAIL|SKIP` line per check with a fix hint and exits 0 only if none is `FAIL`.
- Given `NODE_ROLE=host|both`, when `doctor.sh` runs, then it additionally FAILs/PASSes the host-only checks; `client` SKIPs them.
- Given any run, then no token, key, tailnet IP, or node name appears in output.
- Given `doctor.sh --check`, then it self-tests side-effect-free, exits 0, and aggregates `--check` for any other present `scripts/*.sh`.

## Design Notes

macOS backend detection: resolve the running `tailscaled` binary path (`pgrep -fl tailscaled` or `ps -ax -o comm=`) and check it is under a Homebrew prefix (`/opt/homebrew` or `/usr/local`), not `/Applications/Tailscale.app/...` — the GUI app's sandboxed helper. WSL PID-1 check: `[ "$(ps -p 1 -o comm=)" = "systemd" ]`.

Self-test sandbox: `doctor.sh --check` creates a `mktemp -d`, writes a synthetic `local.env` and `~/.ssh`-equivalent tree inside it, prepends a temp `bin/` with stub executables for `tailscale`/`tmux`/`claude`/`git` to PATH, runs the check functions against that sandbox (via `HOME`/`WORKSPACES_DIR` overrides), asserts expected PASS/FAIL/SKIP/exit-code outcomes, then removes the sandbox — so the self-test is deterministic regardless of the real host's tools or tailnet state.

## Verification

**Commands:**
- `shellcheck scripts/doctor.sh` -- expected: clean
- `scripts/doctor.sh --check` -- expected: exit 0
- `cp config/local.env.example config/local.env` then edit `NODE_ROLE` to `client`/`host`/`bogus` and run `scripts/doctor.sh` manually -- expected: exit 0/host-checks-run/exit 2 respectively, matching the I/O matrix

## Suggested Review Order

**Role resolution**

- Entry point — three-tier precedence (file wins, then env var, then `--role`), validated against `host|client|both`.
  [`doctor.sh:89`](../../scripts/doctor.sh#L89)

**Common + host-gated checks**

- Tool/tailnet/ssh-perm checks run for any valid role.
  [`doctor.sh:208`](../../scripts/doctor.sh#L208)

- Host-only checks (SSH advertised, workspaces dir, platform contract) gated on `host|both`; `client` SKIPs them.
  [`doctor.sh:306`](../../scripts/doctor.sh#L306)

- macOS Homebrew-vs-GUI-app backend detection via the running `tailscaled` process path.
  [`doctor.sh:258`](../../scripts/doctor.sh#L258)

- WSL PID-1 systemd check, dispatched per-platform from `check_platform_contract`.
  [`doctor.sh:276`](../../scripts/doctor.sh#L276), [`doctor.sh:286`](../../scripts/doctor.sh#L286)

**Self-test (AD-8 self-checking)**

- Hermetic sandbox: PATH-stubbed tools, `mktemp -d`, asserts every I/O-matrix row plus role-precedence and platform-contract branches.
  [`doctor.sh:686`](../../scripts/doctor.sh#L686)

**Peripherals**

- Committed config template consumed by role resolution above.
  [`config/local.env.example:2`](../../config/local.env.example#L2)

- CLI arg parsing (`--role`, `--check`, `-h`) and the exit-code contract.
  [`doctor.sh:721`](../../scripts/doctor.sh#L721)
