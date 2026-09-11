---
title: 'Enroll a client key on a fallback host and connect with `--fallback`'
type: 'feature'
created: '2026-09-11'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '182b399da05784e7ce8728692c24d39fc5fc9370'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Story 3.1 gave a fallback host hardened OpenSSH, but there is no way for a client to get its key onto that host or to reach it through `connect.sh` — a reader has to hand-edit `authorized_keys` and run raw `ssh`.

**Approach:** Add `scripts/enroll.sh` (host-side, appends one validated ed25519 pubkey to `authorized_keys`), extend `connect.sh` with a `--fallback <node> <workspace>` mode that execs plain `ssh` instead of `tailscale ssh`, and document the client-side key-generation + delivery + `~/.ssh/config` flow in `docs/fallback-openssh.md`.

## Boundaries & Constraints

**Always:** `enroll.sh` runs only when `NODE_ROLE=host|both` and `FALLBACK_SSHD=1`; otherwise exit 2, one line on stderr, no side effects. Input is exactly one ed25519 public key (file arg or stdin) — anything else (wrong key type, multiple keys, garbage) is the same exit-2 refusal. Append to `~/.ssh/authorized_keys` only if an equivalent key (same algorithm + base64 material, ignoring the trailing comment) isn't already present; enforce `~/.ssh` 0700 and `authorized_keys` 0600 every run. Never print, log, or echo the key material. `connect.sh --fallback <node> <workspace>` execs `ssh -t <node> -- '$HOME/agentic-workstation/scripts/start-claude.sh' <workspace>` (single-quoted `$HOME`, expanded remotely, matching `connect()`'s existing convention) relying entirely on the client's own untracked `~/.ssh/config`; it never probes for or lists fallback hosts, and behavior with no `--fallback` flag is byte-for-byte unchanged (AD-3). Both scripts follow AD-8 (bash-3.2-safe, `set -euo pipefail`, no `jq`, shellcheck-clean) and expose `--check`.

**Ask First:** none anticipated.

**Never:** No ACL/keys file committed to the repo. No change to `doctor.sh`'s aggregation logic — `run_other_scripts_check()` (doctor.sh:1234) already globs every executable `scripts/*.sh`, so `enroll.sh --check` is picked up automatically once the file exists and is executable; do not hand-wire it in. No weakening of the Tailscale-SSH-primary path or of story 3.1's hardening checks.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First enrollment | Valid ed25519 pubkey, not yet in `authorized_keys`, `FALLBACK_SSHD=1`, role host/both | Key appended, perms fixed, exit 0, no key echoed | N/A |
| Re-run, already enrolled | Same key (byte-identical or same algo+material, different comment) | No duplicate line added, exit 0 | N/A |
| Wrong key type / multiple keys / garbage | e.g. `ssh-rsa ...` or a private key | Exit 2, one stderr line, `authorized_keys` untouched | Refusal, no side effects |
| Fallback disabled | `FALLBACK_SSHD=0` (default) or unset | Exit 2, one stderr line | Refusal |
| Client role | `NODE_ROLE=client` | Exit 2, one stderr line | Refusal |
| `connect.sh --fallback <node> <workspace>` | Valid workspace name | execs `ssh -t <node> -- '$HOME/agentic-workstation/scripts/start-claude.sh' <workspace>` | N/A |
| `connect.sh` without `--fallback` | Same args as before this story | Unchanged `tailscale ssh` behavior | N/A |

</frozen-after-approval>

## Code Map

- `scripts/start-claude.sh` -- `resolve_and_validate_role()` and its `host|both` gate: `enroll.sh` reuses this exact role requirement (inverse of `connect.sh`'s `client|both`), same `CONFIG_FILE`/sourcing convention.
- `scripts/connect.sh` -- `die2()` (L58), `usage()` (L33), `validate_workspace_name()` (L67), `resolve_and_validate_role()` (L83), `connect()` (L123, execs `tailscale ssh` today), `discover_peers()` (L148, `set -f`/word-split convention to mirror if `--fallback` needs its own arg scan), `write_stub_tools()` (L183, add an `ssh` stub alongside the existing `tailscale` stub, same `*_ARGV_FILE` capture pattern), `main()` (L649, dispatches on `$#`/flags today — add `--fallback` before the positional-arg cases).
- `scripts/doctor.sh` -- `run_other_scripts_check()` (L1234): confirms no doctor.sh change needed; `FALLBACK_SSHD` default (L119) for reference only.
- `docs/fallback-openssh.md` -- `## Caveat: no client-side automation yet` (L224-230): replace with a new numbered `## 7. Enroll a client key` section (keygen with passphrase + ssh-agent, out-of-band delivery e.g. `tailscale file cp`, running `enroll.sh` on the host, adding the `Host <node>` entry from `config/ssh_config.example`, then `connect.sh --fallback <node> <workspace>`).
- `config/ssh_config.example` -- existing `Host <node>` template (already ships from story 2.3); add a comment noting the target host needs `FALLBACK_SSHD=1` and a running hardened sshd — closes the gap deferred in `deferred-work.md` (source: spec-2-3).

## Tasks & Acceptance

**Execution:**
- [x] `scripts/enroll.sh` -- new script: role-gate `host|both`, read pubkey from `$1` file or stdin, validate single ed25519 line, dedupe-aware append to `~/.ssh/authorized_keys`, fix `~/.ssh` 0700 / `authorized_keys` 0600, never print key material, `--check` hermetic self-test (temp `$HOME` sandbox), `-h`/`--help` -- implements this story's core AC
- [x] `scripts/connect.sh` -- add `--fallback <node> <workspace>` mode execing plain `ssh -t`, add an `ssh` stub to `write_stub_tools()`, add `selftest_case_fallback_*` covering the happy path and the unchanged-without-flag case -- implements the connect-side AC
- [x] `docs/fallback-openssh.md` -- add `## 7. Enroll a client key` section, remove the now-stale "no client-side automation yet" caveat -- implements the doc AC
- [x] `config/ssh_config.example` -- add the `FALLBACK_SSHD=1`/running-sshd precondition comment -- closes a scoped deferred-work item

**Acceptance Criteria:**
- Given `NODE_ROLE=host|both` and `FALLBACK_SSHD=1`, when `scripts/enroll.sh <pubkey-file>` (or piped on stdin) runs with a valid single ed25519 key, then it appends the key only if not already present, fixes `~/.ssh`/`authorized_keys` permissions, and never prints the key
- Given `FALLBACK_SSHD` isn't `1`, the input isn't a single ed25519 pubkey, or `NODE_ROLE=client`, when `enroll.sh` runs, then it exits 2 with one stderr line
- Given the client guide section in `docs/fallback-openssh.md`, then it covers per-client keygen with passphrase, never copying a private key, out-of-band delivery, and the `~/.ssh/config` `Host <node>` entry from `config/ssh_config.example`
- Given a client `~/.ssh/config` entry for `<node>`, when `scripts/connect.sh --fallback <node> <workspace>` runs, then it execs `ssh -t <node> -- "$HOME/agentic-workstation/scripts/start-claude.sh" <workspace>`, and `connect.sh` without `--fallback` is unchanged
- Given both scripts, then `enroll.sh` exposes `--check`, both conform to AD-8, and `doctor.sh` aggregates `enroll.sh --check` via its existing dynamic script glob

## Spec Change Log

## Design Notes

Dedupe by comparing the key-type + base64-material fields only (`awk '{print $1, $2}'`-equivalent), ignoring the trailing comment — two lines with the same key but different comments must count as a duplicate, matching sshd's own key-matching semantics. `connect()`'s existing single-quoted `'$HOME/...'` convention (expanded remotely, since `SSH_USER`'s home may differ) applies identically to the new `--fallback` exec — do not double-quote it. `--fallback` mode does not go through `resolve_ssh_user()`/`SSH_USER` at all: the user identity comes entirely from the client's own `~/.ssh/config` `Host <node>` stanza.

## Verification

**Commands:**
- `shellcheck scripts/enroll.sh scripts/connect.sh` -- expected: no warnings
- `scripts/enroll.sh --check` -- expected: PASS on all self-test cases
- `scripts/connect.sh --check` -- expected: PASS including new `--fallback` cases
- `scripts/doctor.sh --check` -- expected: PASS, including `other-script:enroll.sh`
- `gitleaks protect --staged` (pre-commit hook) -- expected: clean

**Manual checks (if no CLI):**
- `docs/fallback-openssh.md` reads coherently end-to-end; the new client section cross-links `config/ssh_config.example` and the existing host-setup sections

## Suggested Review Order

**Enrollment core: validate, then append safely**

- Entry point: reads the key from a file arg or stdin, gates on role, hands off to validation then enrollment.
  [`enroll.sh:676`](../../scripts/enroll.sh#L676)

- Single-key format check — fixed-prefix/length shape check instead of a base64 decoder, plus the CRLF-strip fix from review.
  [`enroll.sh:123`](../../scripts/enroll.sh#L123)

- The dedupe fix confirmed independently by all three review layers: recognizes a leading key-restriction-options field so a hardened `authorized_keys` entry never gets silently duplicated unrestricted.
  [`enroll.sh:192`](../../scripts/enroll.sh#L192)

- Role + `FALLBACK_SSHD=1` gate, mirroring `start-claude.sh`'s `host|both` gate plus the fallback-specific requirement.
  [`enroll.sh:82`](../../scripts/enroll.sh#L82)

**Connect-side: the new `--fallback` mode**

- Dispatch: `--fallback` is intercepted before the positional-arg cases, unchanged behavior otherwise.
  [`connect.sh:871`](../../scripts/connect.sh#L871)

- Execs plain `ssh` instead of `tailscale ssh`, bypassing `SSH_USER` entirely; the option-injection guard on `<node>` closes a review finding.
  [`connect.sh:164`](../../scripts/connect.sh#L164)

**Guide deliverable**

- New client-side section: keygen, out-of-band delivery, running `enroll.sh`, then `connect.sh --fallback`.
  [`fallback-openssh.md:224`](../../docs/fallback-openssh.md#L224)

- Never-copy-the-private-key framing, the doc's core safety claim for this section.
  [`fallback-openssh.md:249`](../../docs/fallback-openssh.md#L249)

**Test coverage (peripheral)**

- The case that specifically proves the dedupe fix: a `command=...`-prefixed existing entry doesn't get duplicated.
  [`enroll.sh:400`](../../scripts/enroll.sh#L400)

- Proves `connect.sh` without `--fallback` is byte-for-byte unchanged (AD-3): still execs `tailscale ssh`, never touches the new `ssh` stub.
  [`connect.sh:788`](../../scripts/connect.sh#L788)
