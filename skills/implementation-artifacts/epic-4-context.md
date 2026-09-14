# Epic 4 Context: Close the retrospective's actionable follow-through

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Close three small, fix-now findings that the epic 1–3 sprint retrospective
routed as remediation or spec-reconciliation work, each traceable to a
recorded source (`skills/implementation-artifacts/epic-3-retro-2026-09-11.md`,
action items 2, 3, 4). This epic is deliberately narrow: it does not touch the
two retro items that need a second tailnet node (the M1 protocol run and the
fallback-host end-to-end check), which stay with the owner. What it does cover
are three diagnosability/consistency gaps a single machine can verify: an
undocumented session-loss edge case, an inconsistent error-visibility pattern
across scripts, and a stale PRD sentence that contradicts the no-`jq`
architecture rule.

## Stories

- Story 4.1: Warn that a self-terminated session does not resume
- Story 4.2: Make config sourcing consistent across the scripts
- Story 4.3: Reconcile the PRD's discovery wording with the implementation

## Requirements & Constraints

- Every node config declares its role (`host`, `client`, `both`) in a
  gitignored local config file; scripts must read the role only from there,
  never from a committed file (FR17). This is the requirement Story 4.2's
  fix must not violate while making error visibility consistent.
- Reconnection after a network drop must take under a minute and lose no
  session state; a reconnect that exceeds this or loses state is a defect,
  not an accepted limitation (NFR2). Story 4.1 addresses a related but
  distinct failure mode — the `claude` process dying on its own, not a
  network drop — that this NFR does not cover but that erodes the same
  underlying continuity goal.
- Host discovery must be described the way it is actually implemented:
  parsing plain-text `tailscale status` output, never `--json` plus `jq`,
  and never a committed host list (Story 4.3's target requirement). The
  intent — discovery always comes from live `tailscale status`, never a
  static list — must survive the wording fix unchanged.
- Every self-tested script exposes `--check` with no side effects, and
  `doctor.sh --check` aggregates the other five scripts' self-tests; all
  affected scripts must keep passing this after each story's change, and
  `shellcheck` must stay clean.
- Each story closes by marking its source record as addressed: Story 4.1 and
  4.2 each clear a `deferred-work.md`-tracked finding, and Story 4.3 clears
  the same tracked divergence for the PRD wording.

## Technical Decisions

- **AD-4 (Persistence is tmux; Claude Code resume is recovery only):** a
  workspace session is exactly one tmux session named `claude-<workspace>`,
  created attach-or-create (`tmux new -A -s claude-<workspace>`) so reconnect
  is idempotent. Claude Code runs inside it as `claude -n claude-<workspace>`
  so a lost tmux server can be recovered with
  `claude --resume claude-<workspace>`. A dropped connection must never
  terminate the tmux session — only `stop.sh` does, for the one session named
  on its command line. Story 4.1's documentation must describe the
  self-terminated-process case as consistent with this same recovery pattern
  (already documented for the host-reboot case), not as a new mechanism.
- **AD-8 (Scripts are portable bash, one verb per file, self-checking):**
  every script is `bash 3.2`-compatible, passes `shellcheck`, parses
  `tailscale status` text output directly (no `jq`, no shared library, no
  Python), and exposes a side-effect-free `--check` self-test that
  `doctor.sh` aggregates. This constrains all three stories: Story 4.1's
  `status.sh` change must add no new dependency; Story 4.2's config-sourcing
  fix must stay within plain bash; Story 4.3's PRD rewrite must match this
  rule exactly (no `jq`, plain-text `tailscale status` parsing).
- Scripts never depend on each other except `connect.sh` invoking
  `start-claude.sh` on the host by absolute path; `config/local.env` is read,
  never written, by scripts — relevant to Story 4.2 since the fix is about
  how that read happens, not about changing what is read.
- The six scripts (`connect.sh`, `doctor.sh`, `enroll.sh`, `start-claude.sh`,
  `status.sh`, `stop.sh`) currently diverge on how `resolve_and_validate_role`
  sources `$CONFIG_FILE`: `doctor.sh` sources it directly (errors surface),
  while `status.sh` and its siblings suppress stderr (`2>/dev/null`), so a
  malformed `config/local.env` is reported by one script and silently
  swallowed by another. Story 4.2 must converge all six on the
  error-surfacing form.

## Cross-Story Dependencies

- All three stories are independent of each other — they touch different
  files (`docs/sessions.md` + `status.sh` for 4.1; the six scripts'
  `resolve_and_validate_role` for 4.2; `prd.md` FR10 for 4.3) and can be built
  in any order.
- Each story closes out a distinct tracked record: Story 4.1 and 4.2 each
  resolve a `deferred-work.md` entry; Story 4.3 resolves the FR10 divergence
  entry also tracked in `deferred-work.md`. None of the three should edit a
  `deferred-work.md` entry belonging to another story, and Story 4.3 must not
  edit any PRD requirement other than FR10's wording.
- This epic excludes (by design, not oversight) two other retro action items
  that need a second tailnet node — the M1 protocol execution and the
  `enroll.sh`/`connect.sh --fallback` end-to-end verification — both of which
  remain owner-tracked outside this epic.
