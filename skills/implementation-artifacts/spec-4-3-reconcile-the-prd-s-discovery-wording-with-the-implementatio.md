---
title: 'Reconcile the PRD''s discovery wording with the implementation'
type: 'chore'
created: '2026-09-13'
status: 'done'
review_loop_iteration: 0
context: []
route: 'one-shot'
baseline_commit: 'd789566a5891c299233543dba8a7e7d7b0baf3c0'
final_revision: '8584f1b'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `prd.md` FR10 said discovery "lists reachable hosts from `tailscale status --json`", which contradicts AD-8's no-`jq` rule and `scripts/connect.sh`'s actual plain-text parsing of `tailscale status` in `discover_peers()`.

**Approach:** Reworded FR10's `connect.sh` clause to describe the implemented plain-text parsing without introducing a bare, undefined `AD-8` cross-reference into reader-facing PRD prose (matching the anti-pattern fix already applied in stories 1.6/2.4/4.1); bumped the PRD's `updated` frontmatter date; marked the originating `deferred-work.md` entry as `addressed_by` this spec. No other PRD requirement was touched.

</frozen-after-approval>

## Suggested Review Order

**Wording fix**

- The actual divergence: `--json`/`jq` language replaced with the true plain-text-parsing behavior.
  [`prd.md:65`](../planning-artifacts/prds/prd-agentic-workstation-2026-09-10/prd.md#L65)

- `discover_peers()` is the ground truth this wording now matches — no `--json`, no `jq`.
  [`connect.sh:191`](../../scripts/connect.sh#L191)

**Peripherals**

- Freshness date bumped to reflect the content edit above.
  [`prd.md:5`](../planning-artifacts/prds/prd-agentic-workstation-2026-09-10/prd.md#L5)

- The tracked divergence this story closes.
  [`deferred-work.md:140`](deferred-work.md#L140)
