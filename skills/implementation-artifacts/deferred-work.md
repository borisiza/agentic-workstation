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

- source_spec: `skills/implementation-artifacts/spec-2-3-connect-from-a-client-to-a-host-workspace-with-one-command.md`
  summary: scripts/connect.sh does not check that the `tailscale` binary is actually installed before its `exec tailscale ssh ...` (connect mode) or `tailscale status` call (discovery mode); a missing binary fails with a raw "command not found" (exit 127) or a misleading "is tailscaled running?" message instead of the script's own exit-2/one-line convention.
  evidence: blind-hunter review of story 2.3 flagged this; extends the identical, already-deferred "tool presence not preflighted" pattern from scripts/start-claude.sh (story 2.1) to this new script -- doctor.sh already gatekeeps tool presence as a common check, so this is defense-in-depth, not a required guard for this story's AC.

- source_spec: `skills/implementation-artifacts/spec-2-3-connect-from-a-client-to-a-host-workspace-with-one-command.md`
  summary: connect.sh's resolve_ssh_user only rejects the literal string "root"; a whitespace-padded value (` root`) or an SSH_USER containing embedded whitespace/`@` isn't trimmed or rejected, so it could bypass the root check or produce a malformed `user@node` token that only fails at the tailscale layer.
  evidence: blind-hunter and edge-case-hunter reviews of story 2.3 both flagged this; SSH_USER comes from the same trusted, single-operator config/local.env as other unvalidated values in this repo (e.g. WORKSPACES_DIR's own already-deferred lack of absolute-path validation), so this is a self-inflicted-misconfiguration-only risk, not a required guard.

- source_spec: `skills/implementation-artifacts/spec-2-3-connect-from-a-client-to-a-host-workspace-with-one-command.md`
  summary: discover_peers' offline-peer detection matches only an exact last-field token of "offline"; real `tailscale status` output can append other suffixes (e.g. tags, "expired") this repo has not verified against a live tailnet, so some offline or otherwise-unreachable peers could still be listed as connectable.
  evidence: edge-case-hunter review of story 2.3 flagged this; verifying the exact set of suffixes `tailscale status` can emit requires a live tailnet not available in this environment, so a robust fix needs empirical confirmation rather than a blind patch.

- source_spec: `skills/implementation-artifacts/spec-2-3-connect-from-a-client-to-a-host-workspace-with-one-command.md`
  summary: config/ssh_config.example's `Host <node>` template gives no guidance on `StrictHostKeyChecking`/`IdentityFile`/host-key verification, and doesn't mention that the target host needs `FALLBACK_SSHD=1` (config/local.env.example) plus a running sshd for the template to work at all.
  evidence: blind-hunter review of story 2.3 flagged this; this story's AC only requires a minimal `Host <node>` entry with keepalive settings as an optional plain-ssh alternative -- the full hardened-OpenSSH-fallback flow (key hygiene, sshd hardening) is Epic 3's explicit scope (FR18), not this story's.

- source_spec: `skills/implementation-artifacts/spec-2-3-connect-from-a-client-to-a-host-workspace-with-one-command.md`
  summary: README.md's four-layer table still says "Only L1 ... and doctor.sh ... exist today -- connect.sh, enroll.sh, start-claude.sh, status.sh, and stop.sh are this epic's Epic 2/3 build-out targets" -- stale for four of these five scripts (all of Epic 2 now ships), and this story adds the last Epic-2 one without correcting it.
  evidence: blind-hunter review of story 2.3 flagged this; the staleness predates this story (already inaccurate after stories 2.1/2.2 shipped without a README update, per their own script-only scope boundaries), so this is a cross-cutting doc-consistency gap best fixed once rather than patched asymmetrically here.

- source_spec: `skills/implementation-artifacts/spec-2-3-connect-from-a-client-to-a-host-workspace-with-one-command.md`
  summary: skills/planning-artifacts/prds/prd-agentic-workstation-2026-09-10/prd.md (FR10) still describes host discovery as parsing `tailscale status --json`, which contradicts both AD-8 ("no jq") and this story's actual plain-text-parsing implementation.
  evidence: blind-hunter review of story 2.3 flagged this; the PRD predates this story and wasn't touched by it, so reconciling the terminology is a documentation follow-up, not part of this story's scope.

- source_spec: `skills/implementation-artifacts/spec-2-4-survive-a-dropped-link-and-resume-within-a-minute-in-both-di.md`
  summary: docs/sessions.md doesn't warn that if the `claude` process inside `claude-<workspace>` exits or crashes on its own (not via a reboot or `stop.sh`), the tmux pane running it closes too, so the next `connect.sh` reattach silently starts a brand-new conversation instead of resuming the old one.
  evidence: edge-case-hunter review of story 2.4 flagged this; it's inherent behavior of `start-claude.sh`'s `exec claude ...` launch pattern from story 2.1 (this story only documents reconnect flows, it doesn't change that launch pattern), so it's a pre-existing gap surfaced incidentally rather than something this story's diff caused.

- source_spec: `skills/implementation-artifacts/spec-2-4-survive-a-dropped-link-and-resume-within-a-minute-in-both-di.md`
  summary: docs/sessions.md's `cp config/tmux.conf.example ~/.tmux.conf` step silently overwrites any pre-existing `~/.tmux.conf` on the host instead of merging or warning first.
  evidence: edge-case-hunter review of story 2.4 flagged this; it's the same unguarded-`cp`-on-retry pattern already deferred for `config/local.env` (story 2.1's deferred-work entry) and `config/ssh_config.example`-style templates across this repo's onboarding docs, so fixing it only here would diverge from that established, already-accepted convention rather than fix it.

- source_spec: `skills/implementation-artifacts/spec-2-4-survive-a-dropped-link-and-resume-within-a-minute-in-both-di.md`
  summary: **AC sin ejecutar — deuda aceptada explícitamente.** El protocolo M1 (A→B iniciar sesión, cortar el enlace, reconectar en <60s con contexto intacto y tiempo medido; luego B→A conviviendo con la sesión A→B) nunca se ejecutó: requiere dos nodos tailnet reales y el entorno de build tiene una sola máquina. La historia 2.4 se promovió a `done` por decisión del owner con esta deuda anotada, no porque el AC se haya cumplido.
  evidence: verificado en una sola máquina lo verificable — `config/tmux.conf.example` carga en tmux, la sesión sobrevive al detach y el scrollback se preserva al reattach, CI hygiene verde. NO verificado: reconexión entre nodos tras caída de red (NFR2), coexistencia de sesiones A→B y B→A (FR8), y la métrica de éxito M1 del PRD. Hasta ejecutarlo, la promesa central del MVP (G3) carece de evidencia empírica.

- source_spec: `skills/implementation-artifacts/spec-3-1-opt-a-host-into-hardened-key-only-openssh-over-the-tailnet.md`
  summary: check_authorized_keys_perms only checks octal permission bits on ~/.ssh and authorized_keys; it never checks file/directory ownership (OpenSSH's StrictModes also rejects keys over ownership mismatches) and never checks that authorized_keys actually contains a real key line, so a correctly-permissioned but empty or wrong-owner file still reports PASS.
  evidence: edge-case-hunter and blind-hunter reviews of story 3.1 both flagged this; the story's AC only asks for 0700/0600 permission verification, not ownership or content validation, so this extends beyond the literal acceptance criteria rather than violating it.

- source_spec: `skills/implementation-artifacts/spec-3-1-opt-a-host-into-hardened-key-only-openssh-over-the-tailnet.md`
  summary: docs/fallback-openssh.md gives no guidance on verifying the host's SSH key fingerprint out-of-band on first connection (TOFU trust with no verification instructions), and has no decommission/rollback section (reverting FALLBACK_SSHD to 0, disabling Remote Login/sshd, clearing authorized_keys).
  evidence: blind-hunter review of story 3.1 flagged both; identical classes of gap (missing host-key-TOFU explanation, missing decommission section) were already deferred for the sibling node-*.md guides in stories 2.3 and 2.4 respectively, so this is a known, already-accepted pattern across all onboarding docs rather than a defect unique to this story.

- source_spec: `skills/implementation-artifacts/spec-3-1-opt-a-host-into-hardened-key-only-openssh-over-the-tailnet.md`
  summary: doctor.sh's sshd-running check (pgrep -x sshd) can false-negative on Linux distros where sshd is socket-activated (ssh.socket, no persistent process until first connection) — the same class of on-demand-startup gap already documented as a caveat for macOS's launchd-spawned sshd.
  evidence: edge-case-hunter review of story 3.1 flagged this; the guide's own documented setup command (systemctl enable --now ssh) results in a persistent daemon by default on the Debian/Ubuntu and RHEL/Fedora targets this guide covers, so it doesn't manifest under the documented flow — only a risk for non-default distro configurations.

- source_spec: `skills/implementation-artifacts/spec-3-1-opt-a-host-into-hardened-key-only-openssh-over-the-tailnet.md`
  summary: FALLBACK_SSHD isn't validated against {0,1} the way NODE_ROLE is (e.g. FALLBACK_SSHD=true silently behaves like 0, since only the literal string "1" takes the fallback branch), and docs/fallback-openssh.md isn't linked from node-linux.md or node-wsl.md even though it documents Linux/RHEL install steps too, reducing discoverability for non-macOS hosts that might need it.
  evidence: edge-case-hunter and blind-hunter reviews of story 3.1 flagged these; both are minor robustness/discoverability nits with no security impact (an invalid FALLBACK_SSHD value fails safe into "fallback disabled" behavior) and outside this story's Code Map, which only scoped the node-macos.md forward-reference.

- source_spec: `skills/implementation-artifacts/spec-3-1-opt-a-host-into-hardened-key-only-openssh-over-the-tailnet.md`
  summary: docs/fallback-openssh.md's Linux/WSL setup step (`sudo systemctl enable --now ssh`) has no fallback for WSL distros that don't have systemd enabled (pre-`wsl.conf systemd=true`), where that command fails outright and a different startup path (e.g. `sudo service ssh start`) is needed instead.
  evidence: blind-hunter review of story 3.1 flagged this; it's a genuine gap in this story's own new doc, not covered by any existing deferred-work entry, but doesn't block the story's AC since the guide's primary documented flow (systemd-enabled WSL, per story 1.5's own WSL2 prerequisite) works as written.

- source_spec: `skills/implementation-artifacts/spec-3-1-opt-a-host-into-hardened-key-only-openssh-over-the-tailnet.md`
  summary: docs/fallback-openssh.md's `sshd -T` verification step (section 3) only checks the four restrictive hardening settings and never confirms `PubkeyAuthentication yes` is actually active, so a host with pubkey auth disabled by some prior local config could follow every step in the guide and still be unable to log in, with no diagnostic pointing at the real cause. Separately, `check_sshd_hardening()` runs `sshd -T` without `sudo` (unlike the guide's own manual `sudo sshd -T` instruction) — unconfirmed in this sandboxed environment whether this ever causes a permission-related false FAIL on a real host, since sshd -T is commonly usable unprivileged but this couldn't be verified empirically here.
  evidence: blind-hunter review of story 3.1 flagged both; adding a 5th check would exceed this story's frozen `<frozen-after-approval>` scope (the four named settings only), so it's recorded for a future decision rather than patched in-scope. The sudo risk is real but unconfirmed — worth a real-host smoke test before the next story that depends on this check.

- source_spec: `skills/implementation-artifacts/spec-3-2-enroll-a-client-key-on-a-fallback-host-and-connect-with-fall.md`
  summary: Neither `scripts/enroll.sh` nor `docs/fallback-openssh.md` documents how to revoke a lost/compromised client key or offboard a laptop from a fallback host — `enroll.sh` only appends, there is no removal command or manual-removal instructions.
  evidence: blind-hunter review of story 3.2 flagged this; a real gap for a "key-only access" story, but this story's AC only covers enrollment and connecting, not revocation, and extends beyond the literal scope.

- source_spec: `skills/implementation-artifacts/spec-3-2-enroll-a-client-key-on-a-fallback-host-and-connect-with-fall.md`
  summary: `enroll.sh` only gates on `NODE_ROLE=host|both` and `FALLBACK_SSHD=1` — it never confirms the host's sshd is actually hardened (story 3.1's four settings) before enrolling a key, so an operator who sets `FALLBACK_SSHD=1` before finishing the earlier setup steps can enroll a key on a host that still allows password auth or hasn't restricted `AllowUsers`, with nothing warning them.
  evidence: blind-hunter review of story 3.2 flagged this; verifying sshd hardening is `doctor.sh`'s job (story 3.1), not `enroll.sh`'s — a cross-script check is out of this story's own script boundary.

- source_spec: `skills/implementation-artifacts/spec-3-2-enroll-a-client-key-on-a-fallback-host-and-connect-with-fall.md`
  summary: `config/ssh_config.example`'s `Host <node>` template still has no `IdentityFile` guidance pointing at a non-default key path (e.g. `~/.ssh/id_ed25519_fallback`, the name `docs/fallback-openssh.md` section 7 itself recommends), so the whole `--fallback` connect flow silently depends on the key staying loaded in the local ssh-agent, with no mention that `ssh-add` must be re-run after reboot/logout.
  evidence: blind-hunter review of story 3.2 flagged this; a continuation of the `IdentityFile`/`StrictHostKeyChecking` gap already deferred against story 2.3 (only the `FALLBACK_SSHD=1`/running-sshd precondition comment was closed by this story), not a new defect.

- source_spec: `skills/implementation-artifacts/spec-3-2-enroll-a-client-key-on-a-fallback-host-and-connect-with-fall.md`
  summary: `docs/fallback-openssh.md` section 7 has no explicit "test the raw connection" verification step and no warning about the client's own private-key file needing correct permissions, breaking the pattern sections 1-6 all follow (each ends with an explicit verification command).
  evidence: blind-hunter review of story 3.2 flagged this; a docs-completeness gap, not required by this story's AC.

- source_spec: `skills/implementation-artifacts/spec-3-2-enroll-a-client-key-on-a-fallback-host-and-connect-with-fall.md`
  summary: No `doctor.sh` check verifies end-to-end that a client key was actually enrolled and the fallback path is reachable — `enroll.sh --check` is a hermetic self-test only, not a live connectivity check, so "did enrollment actually work" is left to manual inspection.
  evidence: blind-hunter review of story 3.2 flagged this; a real observability gap, but adding a live-connectivity doctor.sh check is a design decision beyond this story's scope.

- source_spec: `skills/implementation-artifacts/spec-3-2-enroll-a-client-key-on-a-fallback-host-and-connect-with-fall.md`
  summary: `docs/fallback-openssh.md` section 7's "Deliver the public key out-of-band" advice ("Any other out-of-band channel works too") gives no concrete alternative for when Taildrop (`tailscale file cp`) is disabled by tailnet ACL policy, a common lockdown.
  evidence: blind-hunter review of story 3.2 flagged this; a minor docs-polish gap, not required by this story's AC.
