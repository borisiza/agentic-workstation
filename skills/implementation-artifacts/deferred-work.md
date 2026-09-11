- source_spec: `skills/implementation-artifacts/spec-1-2-declare-the-node-role-and-verify-readiness-with-doctor-sh.md`
  summary: doctor.sh sources config/local.env without checking its permissions, so a world/group-writable local.env would let another local user on the same machine achieve code execution as the node operator.
  evidence: verification-gap/edge-case review of story 1.2 flagged this; fixing it well requires a design call (refuse to source, warn-only, or auto-fix perms) rather than a one-line patch, and config/local.env is a single-user, gitignored file so the realistic blast radius on a personal machine is low — deferred rather than blocking this story.

- source_spec: `skills/implementation-artifacts/spec-1-2-declare-the-node-role-and-verify-readiness-with-doctor-sh.md`
  summary: doctor.sh's run_other_scripts_check invokes each future scripts/*.sh --check with no timeout, so a hung sibling script would hang doctor.sh --check indefinitely.
  evidence: edge-case review of story 1.2 flagged this; no other scripts/*.sh exist yet so it cannot manifest today, and a portable timeout on bash 3.2/macOS needs coreutils (`timeout` is not built in, only GNU `timeout`/`gtimeout`) — worth revisiting once story 1.3+ actually adds a sibling script.

- source_spec: `skills/implementation-artifacts/spec-1-3-enroll-a-linux-host.md`
  summary: docs/node-linux.md doesn't tell the reader to hold the Tailscale package version after pinning it (apt-mark hold / dnf versionlock), so a routine system upgrade can silently move the host off 1.102.3.
  evidence: blind-hunter review of story 1.3 flagged this; not part of the story's stated scope (install + enroll, not long-term version enforcement) and low blast radius for a personal PoC node.

- source_spec: `skills/implementation-artifacts/spec-1-3-enroll-a-linux-host.md`
  summary: docs/node-linux.md doesn't mention that some tailnets require new-device approval in the admin console before the device is reachable, which could strand a reader whose tailnet enforces it with no diagnostic pointer.
  evidence: blind-hunter review of story 1.3 flagged this; the epic's stated assumption is the tailnet's unmodified default (check-mode ACL, no extra policy), under which personal tailnets don't require manual approval, so this doesn't block the common case.

- source_spec: `skills/implementation-artifacts/spec-1-3-enroll-a-linux-host.md`
  summary: docs/node-linux.md has no prerequisites/overview section (assumed outbound network access, sudo rights, an existing tailnet account) before the multi-stage procedure starts.
  evidence: blind-hunter review of story 1.3 flagged this; an organizational nice-to-have, not required by the story's Given/When/Then acceptance criteria.

- source_spec: `skills/implementation-artifacts/spec-1-3-enroll-a-linux-host.md`
  summary: docs/node-linux.md gives no idempotency/rollback guidance if enrollment fails partway (e.g. after `tailscale up --ssh` but before `doctor.sh` passes), and re-running step 4's `cp config/local.env.example config/local.env` would silently overwrite an existing `config/local.env`.
  evidence: blind-hunter and edge-case-hunter reviews of story 1.3 both flagged partial-failure/re-run gaps; worth a follow-up doc revision once real onboarding attempts surface which failure modes actually recur.

- source_spec: `skills/implementation-artifacts/spec-1-3-enroll-a-linux-host.md`
  summary: docs/node-linux.md doesn't clarify that `NODE_ROLE=host` is a purely local, repo-side setting with no corresponding Tailscale-side concept (e.g. a device tag), nor that `autogroup:self` only authorizes devices owned by the same tailnet identity — a reader could misattribute a connection failure.
  evidence: edge-case-hunter review of story 1.3 flagged this; a real conceptual gap but secondary to the primary enrollment path this story's AC covers.

- source_spec: `skills/implementation-artifacts/spec-1-3-enroll-a-linux-host.md`
  summary: scripts/doctor.sh --check (its self-test) is never invoked in CI (.github/workflows/hygiene.yml only runs shellcheck + gitleaks) and no other invocation exists repo-wide, so nothing verifies doctor.sh's actual PASS/SKIP contract stays consistent with what onboarding docs tell readers to expect.
  evidence: verification-gap review of story 1.3 confirmed this by reading hygiene.yml and searching the repo for any `doctor.sh --check` invocation; wiring doctor.sh --check into CI is a scripts/CI change, out of this docs-only story's boundaries (`Never: do not modify scripts/doctor.sh or any other script`).

- source_spec: `skills/implementation-artifacts/spec-1-4-enroll-a-macos-host.md`
  summary: docs/node-linux.md and docs/node-macos.md both use `<repo-url>` as a placeholder in their clone step without listing it alongside `<node>`/`<user>` in the Conventions section, and both let re-running `cp config/local.env.example config/local.env` silently overwrite a previously-configured `config/local.env`, and neither handles `git pull` hitting diverged history on a re-attempt.
  evidence: blind-hunter and edge-case-hunter reviews of story 1.4 both flagged these; identical pattern already shipped (and accepted) in story 1.3's node-linux.md, so this is a cross-cutting doc-consistency gap best fixed once across both guides rather than patched asymmetrically in just one.

- source_spec: `skills/implementation-artifacts/spec-1-4-enroll-a-macos-host.md`
  summary: neither node-linux.md nor node-macos.md tells a headless/GUI-less reader how to complete `tailscale up --ssh`'s first-run login or the check-mode re-authentication browser prompt when no local browser is available on the node being enrolled.
  evidence: edge-case-hunter review of story 1.4 flagged this; both guides assume an interactive desktop session, which covers the story's stated scope (a Mac/Linux desktop being enrolled) but would strand a genuinely headless server reader.

- source_spec: `skills/implementation-artifacts/spec-1-4-enroll-a-macos-host.md`
  summary: scripts/doctor.sh's check_macos_backend (doctor.sh:258) hardcodes the Homebrew prefixes `/opt/homebrew/*`/`/usr/local/*` instead of checking against `$(brew --prefix)`, so a custom `HOMEBREW_PREFIX` install would FAIL the check even with a correctly running Homebrew `tailscaled`; it also can't distinguish "no tailscaled running" from "both the GUI app's and Homebrew's tailscaled running simultaneously" — both report the same FAIL with the same generic hint.
  evidence: edge-case-hunter review of story 1.4 flagged this while cross-checking docs/node-macos.md against the real check; it's a scripts/doctor.sh behavior gap, out of this docs-only story's boundaries (`Never: do not modify scripts/doctor.sh or any other script`), and non-default Homebrew prefixes are uncommon.

- source_spec: `skills/implementation-artifacts/spec-1-5-enroll-a-windows-host-via-wsl2.md`
  summary: docs/node-wsl.md has no step-0 prerequisite confirming WSL2 itself (vs WSL1) is installed and set as default, nor the Windows Virtual Machine Platform feature / initial reboot that first-time `wsl --install` requires — the guide starts at `wsl --version`, assuming a working WSL2 install already exists.
  evidence: blind-hunter and edge-case-hunter reviews of story 1.5 both flagged this; the story's own AC Given clause ("Given Windows with WSL >= 2.4.4") explicitly assumes WSL2 is already installed as a starting precondition, so it's in-scope-adjacent but not required by this story's acceptance criteria — worth folding into Story 1.6's README onboarding index instead.

- source_spec: `skills/implementation-artifacts/spec-1-5-enroll-a-windows-host-via-wsl2.md`
  summary: none of docs/node-wsl.md, docs/node-linux.md, or docs/node-macos.md gives troubleshooting guidance for `tailscale up --ssh` itself failing (e.g. WSL2's NAT/vEthernet adapter or Windows Firewall blocking the tailnet join) — only the platform-contract/systemd and the security/port checks have documented failure paths.
  evidence: edge-case-hunter review of story 1.5 flagged this for WSL specifically, but the same gap exists in the two already-approved sibling guides; best fixed once across all three rather than patched asymmetrically in just one.

- source_spec: `skills/implementation-artifacts/spec-1-5-enroll-a-windows-host-via-wsl2.md`
  summary: the plain-SSH fallback and the tailscaled-restart manual recovery shim in all three host guides (linux/macos/wsl) assume "a working, locked-down local sshd," but no guide in this repo ever sets one up — that precondition is actually the Epic 3 key-only OpenSSH guide (FR18), which doesn't exist yet.
  evidence: blind-hunter review of story 1.5 flagged this by tracing the recovery caveat's stated precondition back to its source; node-macos.md's spec already names FR18/Epic 3 as the fallback's real owner, so this is a forward-reference gap that resolves itself once Epic 3 ships, not a defect to patch now.

- source_spec: `skills/implementation-artifacts/spec-1-5-enroll-a-windows-host-via-wsl2.md`
  summary: docs/node-wsl.md cites `scripts/doctor.sh` line numbers directly in its prose (`:134`, `:248`, `:276`, `:286`) — a pattern neither node-linux.md nor node-macos.md uses — with nothing in the repo (no test, no CI step) keeping those citations in sync with the script; a future doctor.sh edit that shifts lines would leave the doc silently stale.
  evidence: verification-gap review of story 1.5 confirmed all citations are accurate as of this commit but flagged the fragility; not a defect in this diff, so not patched, but worth a lint/check if this citation style spreads to more docs.

- source_spec: `skills/implementation-artifacts/spec-1-5-enroll-a-windows-host-via-wsl2.md`
  summary: docs/node-wsl.md's Task Scheduler "run whether logged on or not" entry has no guidance for what happens when the Windows account's password changes or expires — Task Scheduler silently stops launching the distro on next restart with no alert, breaking the guide's unattended-reachability guarantee.
  evidence: edge-case-hunter review of story 1.5 flagged this; addressing it well needs either a passwordless/gMSA-style credential approach or an explicit monitoring recommendation, which is a design call beyond a one-line patch.

- source_spec: `skills/implementation-artifacts/spec-1-5-enroll-a-windows-host-via-wsl2.md`
  summary: none of the three host guides (node-linux.md, node-macos.md, node-wsl.md) has a decommission/rollback section (`tailscale logout`/`down`, disabling the relevant daemon, removing WSL's Task Scheduler entry) for removing a host from the tailnet later.
  evidence: blind-hunter review of story 1.5 flagged this for WSL, but it applies equally to the two already-approved guides; cross-cutting doc gap, best added once across all three rather than asymmetrically.

- source_spec: `skills/implementation-artifacts/spec-1-6-set-up-a-client-only-node-and-the-onboarding-readme.md`
  summary: docs/node-client.md's three `cp config/local.env.example config/local.env` steps are unguarded and silently overwrite a previously-configured config/local.env on a guide re-run, extending the same pre-existing pattern already deferred for node-linux.md/node-macos.md to a fourth file.
  evidence: blind-hunter and edge-case-hunter reviews of story 1.6 both flagged this; cross-cutting doc gap across all four node guides, best fixed once rather than patched asymmetrically in just one.

- source_spec: `skills/implementation-artifacts/spec-1-6-set-up-a-client-only-node-and-the-onboarding-readme.md`
  summary: docs/node-client.md gives no guidance for restrictive networks (corporate/campus firewalls blocking Tailscale's UDP hole-punching, DERP relay fallback and its latency) even though the guide explicitly targets "a laptop you carry around" — the client scenario most likely to hit NAT/firewall variability across networks.
  evidence: blind-hunter review of story 1.6 flagged this; addressing it well needs Tailscale-specific network-diagnostics guidance beyond this story's Tasks & Acceptance scope, and no sibling guide (node-linux.md/macos.md/wsl.md) covers this either.

- source_spec: `skills/implementation-artifacts/spec-2-1-start-claude-code-in-a-persistent-tmux-session-on-the-host.md`
  summary: scripts/start-claude.sh does not check that tmux or claude are actually installed/on PATH before its final `exec tmux ...`; a missing tmux fails with a raw "command not found" (exit 127) instead of the script's own exit-2/one-stderr-line convention, and a missing claude leaves a dead tmux session behind instead of failing fast.
  evidence: blind-hunter and edge-case-hunter reviews of story 2.1 both flagged this; doctor.sh already gatekeeps tool presence as a common check before any script should be run, so this is a defense-in-depth nicety rather than a required guard for this story's AC.

- source_spec: `skills/implementation-artifacts/spec-2-1-start-claude-code-in-a-persistent-tmux-session-on-the-host.md`
  summary: the launched Claude Code session runs under `bash -lc` (a login shell), which sources login-init files but not `~/.bashrc`; if a reader's `claude` binary is only on PATH via an rc-file tool (e.g. nvm), the session can fail to find it even though their interactive shell does.
  evidence: blind-hunter review of story 2.1 flagged this; it's a pre-existing convention risk shared with how this whole project assumes `claude`/`tailscale`/`tmux` are already durably on PATH (per doctor.sh's own tool checks), not a regression introduced by this story.

- source_spec: `skills/implementation-artifacts/spec-2-1-start-claude-code-in-a-persistent-tmux-session-on-the-host.md`
  summary: scripts/start-claude.sh mirrors several of scripts/doctor.sh's own pre-existing edge-case gaps by design (per this story's Code Map, which explicitly instructs reusing doctor.sh's role-resolution pattern): `WORKSPACES_DIR="${WORKSPACES_DIR:-$HOME/workspaces}"` dereferences `$HOME` directly (crashes under `set -u` if HOME is unset; silently resolves to `/workspaces` if HOME is set-but-empty), sourcing `config/local.env` means an `exit` inside that file bypasses the `source_rc` diagnostic, `WORKSPACES_DIR` is never required to be an absolute path, and `SCRIPT_PATH` (derived from `BASH_SOURCE[0]:-$0`) is unreliable under unusual invocation styles (e.g. piped execution).
  evidence: edge-case-hunter review of story 2.1 flagged these; each is a verbatim continuation of a pattern already shipped and accepted in scripts/doctor.sh (story 1.2), so fixing it here alone would create inconsistency — best addressed once, across both scripts, in a dedicated hardening pass.

- source_spec: `skills/implementation-artifacts/spec-2-1-start-claude-code-in-a-persistent-tmux-session-on-the-host.md`
  summary: scripts/start-claude.sh's validate_workspace_dir only checks the workspace directory exists (`[ -d ]`), not that it's readable/executable by the current user, so a directory with wrong permissions passes preflight validation and only fails later, less clearly, inside the launched tmux session.
  evidence: edge-case-hunter review of story 2.1 flagged this; not required by the story's AC (which only specifies the directory "does not exist" as a failure case), and a real but low-likelihood misconfiguration for a single-operator host.

- source_spec: `skills/implementation-artifacts/spec-2-1-start-claude-code-in-a-persistent-tmux-session-on-the-host.md`
  summary: the self-test's assert_stderr_one_line helper only checks stderr has exactly one line, never the message content, so two different failure cases (e.g. bad-workspace-name vs. missing-role) could have their diagnostic text accidentally swapped without any self-test case noticing.
  evidence: blind-hunter review of story 2.1 flagged this; a test-rigor improvement, not a functional defect — the AC only requires "one stderr line," not content-matching across cases.

- source_spec: `skills/implementation-artifacts/spec-2-2-list-and-stop-workspace-sessions-on-the-host.md`
  summary: neither status.sh --check nor stop.sh --check covers the tmux binary being entirely absent from PATH, so that failure mode (both scripts currently surface it identically to "no sessions" / "session not found" rather than a distinguishable error) is untested.
  evidence: blind-hunter review of story 2.2 flagged this; start-claude.sh's own self-test has the identical pre-existing gap (always assumes a working tmux stub), so this is a shared pattern across all three scripts, not a defect unique to this story.

- source_spec: `skills/implementation-artifacts/spec-2-2-list-and-stop-workspace-sessions-on-the-host.md`
  summary: status.sh/stop.sh's resolve_and_validate_role only redirects stderr (not stdout) while sourcing config/local.env, so a config file with a stray stdout-writing command would corrupt status.sh's exact-match stdout contract.
  evidence: blind-hunter review of story 2.2 flagged this; the pattern is reused verbatim from start-claude.sh's own already-accepted resolve_and_validate_role (Code Map's explicit reuse instruction), so fixing it here alone would diverge from the sibling script.

- source_spec: `skills/implementation-artifacts/spec-2-2-list-and-stop-workspace-sessions-on-the-host.md`
  summary: status.sh renders the session `created` field in the host's local timezone with no offset/label, which is ambiguous for an operator on a client node in a different timezone from the host.
  evidence: blind-hunter review of story 2.2 flagged this; not required by the story's AC (which only specifies "creation time," no format), and this is a personal PoC tool typically used across nearby timezones.

- source_spec: `skills/implementation-artifacts/spec-2-2-list-and-stop-workspace-sessions-on-the-host.md`
  summary: status.sh's `IFS='|' read` parsing of `tmux list-sessions` output would misalign the name/attached/created fields if an unrelated (non-`claude-*`) tmux session on the same host has a literal `|` character in its name, potentially causing a non-integer compare (`[ "$attached" -gt 0 ]`) to abort the script under `set -e`.
  evidence: blind-hunter and edge-case-hunter reviews of story 2.2 both flagged this; requires an adversarial-or-unusual pre-existing tmux session name from an unrelated tool on a single-operator host, low likelihood but a real latent fragility worth hardening later (e.g. anchor the split from the right, or reject lines with unexpected field counts).

- source_spec: `skills/implementation-artifacts/spec-2-2-list-and-stop-workspace-sessions-on-the-host.md`
  summary: docs/product/poc-plan.md still refers to stop.sh's argument as "session-id" while the shipped script and this spec call it "workspace" (session name is derived as claude-<workspace>).
  evidence: blind-hunter review of story 2.2 flagged this; docs/product/poc-plan.md predates this story and wasn't touched by it, so reconciling the terminology is a documentation follow-up, not part of this story's scope.
