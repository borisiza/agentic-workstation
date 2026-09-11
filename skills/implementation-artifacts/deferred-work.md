- source_spec: `skills/implementation-artifacts/spec-1-2-declare-the-node-role-and-verify-readiness-with-doctor-sh.md`
  summary: doctor.sh sources config/local.env without checking its permissions, so a world/group-writable local.env would let another local user on the same machine achieve code execution as the node operator.
  evidence: verification-gap/edge-case review of story 1.2 flagged this; fixing it well requires a design call (refuse to source, warn-only, or auto-fix perms) rather than a one-line patch, and config/local.env is a single-user, gitignored file so the realistic blast radius on a personal machine is low — deferred rather than blocking this story.

- source_spec: `skills/implementation-artifacts/spec-1-2-declare-the-node-role-and-verify-readiness-with-doctor-sh.md`
  summary: doctor.sh's run_other_scripts_check invokes each future scripts/*.sh --check with no timeout, so a hung sibling script would hang doctor.sh --check indefinitely.
  evidence: edge-case review of story 1.2 flagged this; no other scripts/*.sh exist yet so it cannot manifest today, and a portable timeout on bash 3.2/macOS needs coreutils (`timeout` is not built in, only GNU `timeout`/`gtimeout`) — worth revisiting once story 1.3+ actually adds a sibling script.
