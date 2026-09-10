# PRD Quality Review — Agentic Workstation

## Overall verdict
This is a tight, well-scoped capability-spec PRD for a solo-operator infra tool, and it earns its brevity — the thesis (SSH + tmux + Tailscale to run Claude Code remotely with persistent, secret-free sessions) is coherent and every FR traces back to it. The main gap is mechanical rather than substantive: real deferred decisions and inferences (mosh, native daemon vs tmux, single-user assumption) live only as prose in addendum.md, with none of them surfaced in the PRD itself via `[ASSUMPTION]`, `[NOTE FOR PM]`, or an Open Questions section — fine for hobby stakes, but worth a light pass before calling this "final."

## Decision-readiness — adequate
Trade-offs are actually named, just in the addendum rather than the PRD: "LAN SSH — rejected," "Router port-forward — rejected," "mosh — candidate... evaluate in architecture" (addendum.md, "Transport decision"). The PRD proper has no Open Questions section at all, even though the addendum surfaces at least two genuinely open items (mosh adoption, native Claude Code daemon/`--resume` vs tmux). For a hobby/solo project this is a reasonable choice — the owner is both author and decision-maker — but it means the PRD alone doesn't tell a reader which calls are still live.

### Findings
- **medium** No Open Questions section in prd.md (whole doc) — the addendum flags two real open evaluations (mosh, tmux vs native daemon persistence) that never surface in the PRD as `[NOTE FOR PM]` or Open Questions. *Fix:* add a short "Open Questions" section to prd.md pointing at the addendum's two live evaluations, even if just one line each.

## Substance over theater — strong
No persona padding (one primary + one secondary user, both load-bearing — the secondary drives the "docs must be generic" requirement in FR13/NFR4). NFR1 ("Security is the hard constraint: key-only SSH, no public port exposure...") is specific, not boilerplate. No Vision-statement filler — the Overview states the MVP objective in one sentence and moves to constraints.

## Strategic coherence — strong
Clear thesis: turn a personal Mac into a remotely reachable, persistent, secret-safe agentic dev station over Tailscale. Every FR group (F1–F5) serves it directly, and F5 (public-repo hygiene) is treated as a first-class feature group rather than an afterthought, consistent with "the repository is public" being called out in the Overview. M1–M3 measure the actual thesis (a real reconnect demo, zero gitleaks findings, a cold-start onboarding time) rather than vanity/activity metrics, and the counter-metric ("convenience must not erode security — no metric improvement justifies password auth, port-forwarding, or permission bypasses") is sharp and specific, not generic.

## Done-ness clarity — adequate
Most FRs carry a testable consequence: FR1 ("key-only... password and root login disabled"), FR3 ("sshd reachable only via the tailscale interface"), FR7 ("restores the running session with scrollback"), FR12 ("pre-commit secret scan... blocks accidental secret commits") are all verifiable. NFR2 and M3 pair a bound with a number ("under a minute," "under 30 minutes").

### Findings
- **low** FR9 ("`scripts/doctor.sh` verifies prerequisites... and reports gaps") and FR10 don't state what "covering the session lifecycle" means in a checkable way beyond "the three scripts exist." *Fix:* one line per script naming its exit/output contract (e.g. doctor.sh exit code semantics), or accept this is implementation detail out of PRD scope — worth a one-line call either way.
- **low** NFR2 states a bound ("under a minute, loses no session state") but the PRD has no consequence for the failure case (what happens/what's reported if reconnection exceeds that). Minor given hobby stakes.

## Scope honesty — thin
The Non-Goals section is good and does real work (explicitly excludes phone control, Codex, web portal, Oracle migration, public SSH exposure — Non-goals (MVP)). But the PRD uses none of the `[ASSUMPTION: …]`, `[NOTE FOR PM]`, or Open Questions markup the rubric expects, despite clear unconfirmed inferences baked in silently: single-user assumption (stated as fact, not tagged), "initially a Mac" host, ed25519 as the sole key algorithm, tmux over screen/native daemon (addendum has the reasoning, PRD just states tmux as given in FR6). None of these are wrong calls — the addendum shows real reasoning behind them — but zero are flagged as assumptions in the PRD itself, so a reader of prd.md alone can't tell "confirmed by owner" from "inferred and worth double-checking."

### Findings
- **medium** Zero `[ASSUMPTION]` tags anywhere in prd.md despite several unconfirmed-by-user inferences carried as fact (single-user MVP, ed25519-only, tmux chosen over native Claude Code daemon). *Fix:* tag at minimum the tmux-vs-native-daemon choice and single-user scope, since both are called out as still-evaluated in addendum.md.
- **low** No Assumptions Index — follows from the above; nothing to roundtrip since no assumptions are tagged.

## Downstream usability — n/a (light)
Standalone PRD, no UJs to cross-reference, no downstream architecture/story pipeline declared as dependent on this doc. FR/NFR/M IDs are internally consistent and none are dangling. Minor: no Glossary section, though the domain vocabulary (tailnet, tmux, gitleaks, Tailscale SSH) is small and used consistently enough that a glossary would be overhead here, not missing substance.

## Shape fit — strong
Correctly shaped as a capability spec for a single-operator internal tool — no UJs, no persona padding, SMs are operational (a demo, a scan result, an onboarding time) rather than user-facing engagement metrics. This matches the rubric's "Internal tool, single-operator role" guidance well, and the hobby/solo stakes note is honored: rigor is light but the substance bar (testable FRs, honest non-goals, a real counter-metric) still holds.

## Mechanical notes
- FR numbering is contiguous overall (FR1–FR14) but FR14 is grouped under F1 out of sequence with FR2/FR3 (F1 contains FR1, FR2, FR3, FR14) — a numbering artifact, not a broken reference, low priority.
- No Glossary section; not currently a problem given the PRD's small, consistently-used vocabulary, but would matter if this PRD grows a UX/architecture chain later.
- No Assumptions Index (see Scope honesty above) — nothing indexed because nothing is tagged inline.
- Addendum roundtrips cleanly against the PRD (transport decision, session persistence, poc-plan mapping all trace to a Non-goal, FR, or Roadmap line) — no orphaned addendum content.
