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
