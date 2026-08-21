---
title: Agentic Workstation PoC PRD
status: final
created: 2026-08-21
updated: 2026-08-21
---

# Agentic Workstation — PoC PRD

## 1. Problem

Agent-assisted development today is fragmented: sessions are tied to one specific machine and terminal; agent/skill/MCP/hook/permission configuration is scattered; there is no unified way to start, observe, continue, and stop Claude Code and Codex sessions; safe separation between projects/clients does not exist; moving an environment from a local Mac to a persistent VM requires manual reconstruction; and remote access typically means exposing SSH or a different procedure per provider.

## 2. Vision (beyond this PoC)

`agentic-workstation` is the foundation of a future **Agentic Development OS**: a control plane for operating Claude Code, Codex, and future agent runtimes over local, remote, or self-hosted workspaces, with identity, permissions, isolation, persistence, and observability. The product is provider-neutral in the sense that it does not depend on one provider's internal APIs — not in the sense of hiding real differences between providers.

## 3. Actor and User Journey (PoC scope)

**Primary actor:** Local Developer / Workstation Owner (single user for this PoC).

**Primary journey:**
1. Run diagnostics (`doctor`).
2. Register a workspace.
3. Select a provider.
4. Start a session.
5. Continue from the phone.
6. Request and approve a change.
7. Review tests and diff.
8. Check session status.
9. Stop or recover the session.

**Secondary journeys (short):**
- Recovering an interrupted session.
- Attempting cross-workspace access (must be rejected and logged).
- Provider unavailable or not authenticated (adapter reports an explicit state).
- Mac suspend or restart (documented limitation + recovery procedure).

## 4. Scope

**In scope (this PoC = poc-plan.md Phases 0–8):** Discovery, repository/BMAD scaffold, workspace registry & isolation, provider adapters (Claude Code, Codex), session lifecycle, Remote Control invocation/supervision, local persistence, minimal security.

**Explicitly deferred to roadmap (not built or scoped here):**
- Flutter/Web portal with Firebase Authentication and Google Sign-In (Phase 9).
- Migration to Oracle Cloud ARM64, Tailscale, remote backups/monitoring, **SSH key-only access** (Phase 10 — own future PRD).
- Control plane, real multi-tenancy, per-client roles/tenants.
- Enterprise SSO (SAML, OIDC), full Identity Platform.
- Billing.
- Kubernetes / isolated per-client runners.
- Execution of untrusted third-party code.
- A distributed orchestrator.
- Any abstraction that hides real differences between Claude Code and Codex.

## 5. Outcomes and Success Metrics

**Target outcome:** A Local Developer can start and control Claude Code and Codex sessions from their phone, over a real repository, with isolation between workspaces and without exposing secrets.

**Product-controlled success** (fully within this product's control): workspace registration/validation, adapter common contract, session start/status/stop/recover, isolation, security, diagnostics, reproducible documentation.

**Provider-dependent qualification** (depends on external providers): Claude Code Remote Control validated, Codex Remote Control validated, mobile app/pairing available, eligible account/plan, external service operational. If a capability is externally blocked, the core product is still considered technically correct provided it: (1) detects the block, (2) explains the cause, (3) never fabricates a replacement, (4) keeps the other provider functional, (5) logs the block as an external risk.

**Success metrics:**
1. Guided setup, after prerequisites are met, ≤ 30 minutes.
2. Starting a session ≤ 60 seconds (excluding initial auth and provider latency).
3. Recovery after closing the terminal: documented procedure of ≤ 3 steps.
4. At least 2 simultaneous workspaces supported.
5. 2 adapters implement the common lifecycle contract (doctor/start/status/stop/recover) — see Metric 5 note below.
6. 0 leaks across workspaces during isolation acceptance tests (scoped to the defined test set — see FR-10/10A).
7. 0 secrets detected in repository or logs.
8. Clean install reproducible on a compatible Mac by following documentation alone.
9. `doctor` correctly identifies required/optional dependencies and per-provider blockers.
10. A failure in one provider does not prevent operating or diagnosing the other.
11. Every session traces to exactly one provider and one workspace.
12. Every isolation-rejected operation produces an explicit, auditable, secret-free error.

**Note on Metric 5:** the target is "2 adapters implement a common contract for doctor/start/status/stop/recover, preserving each provider's own capabilities and errors" — not "all functions are identical across providers."

**Counter-metrics:** no Phase 8 security control is traded for setup speed; a failed Codex Remote Control spike is documented as an external blocker, never used as justification to build a custom replacement.

## 6. Terminology

| Term | Definition |
|---|---|
| Workspace | Authorized root directory + configuration (allowed providers, permissions, metadata) an agent can operate in. Unit of isolation. |
| Session | Running instance of a provider (Claude Code or Codex) bound to exactly one workspace, with local non-sensitive metadata. |
| Provider | External agent runtime: Claude Code or Codex. |
| Remote Control | Provider-native capability to continue a session from the phone; `agentic-workstation` invokes/supervises it, never reimplements it. |
| Session Manager (local) | `agentic-workstation` scripts (doctor/start/status/stop) orchestrating sessions locally — not a remote backend. |
| Persistence | A session survives the closing of the terminal that started it. |
| Discovery | Read-only inspection of the Mac environment (Phase 0); never installs, updates, or removes anything. |

## 7. External Dependencies and Spikes

| ID | Item | Risk if it fails | Phase |
|---|---|---|---|
| S1 | **RESOLVED as documented capability, narrowed to a local validation/compatibility spike.** Codex Remote Control is officially documented (see Sources below): pairing flow is ChatGPT/Codex desktop → Settings → Connections → "Control this Mac or PC" → QR → ChatGPT mobile → Remote; host must stay powered, connected, and running the desktop app. CLI (`codex remote-control`, `start`, `pair`, `stop`, `--json`) also targets managed hosts/SSH/devboxes. Remaining unknown: whether *this* Mac/account/rollout/workspace has it enabled — that is what the narrowed spike validates. | If disabled for this account/rollout: documented as an external provider blocker (per FR-13's `remote_control_unavailable`/`plan_not_supported` states), never replaced with a custom implementation | Phase 4 |
| S2 | Spike: Claude Code Remote Control end-to-end | Lower risk — most proven capability today | Phase 3 |
| S3 | Spike: persistence mechanism (evaluate each provider's native daemon before deciding launchd/tmux) | Without this, Phase 6 has no design decision | Phase 6 |
| D1 | Tooling, required vs. optional/installer-or-candidate (see FR-2). **Codex desktop app is Required** — it is the primary pairing path for phone Remote Control per official docs. Codex CLI remains available for adapter start/status/stop/diagnostics and managed-host/SSH/devbox scenarios, but is secondary for the mobile pairing flow. | Blocks `doctor` reporting only for the specific capability, not the diagnostic itself | Phase 0 |
| D2 | A secure system mechanism exists to store/reference credentials without persisting them in repo, workspace config, or logs (Keychain is the preferred candidate to investigate) | Blocks Phase 8 | Phase 8 |
| D3-A | Anthropic account eligible for Claude Code Remote Control | Blocks Phase 3 qualification only | Phase 3 |
| D3-B | ChatGPT account eligible for Codex Remote Control, **including rollout/workspace/admin-control availability** — not just plan tier; must be verified per account by `doctor`, never assumed | Blocks Phase 4 qualification only, independently of D3-A | Phase 4 |
| D4 | Network/pairing path between phone and Mac (provider-specific); for Codex, requires the desktop app host to stay powered on and connected | Outside product control — documented as a limitation | Phase 3-4 |

### Sources (Codex Remote Control)
- https://developers.openai.com/codex/remote-connections
- https://developers.openai.com/codex/developer-commands
- https://developers.openai.com/codex/changelog

## 8. Functional Requirements

### A. Discovery (Phase 0)
- **FR-1** `doctor.sh` inspects macOS, architecture, shell, and tools read-only — including current SSH configuration, open ports, and available projects on disk — never installs, updates, or removes anything; produces `docs/discovery/local-environment.md`. SSH/port findings are inventory only for this PoC (no SSH-based access is built here — see NFR-2 deferral); they inform the future Oracle Cloud PRD.
- **FR-2** `doctor.sh` classifies each dependency as **Required** (compatible macOS, compatible architecture, Git, Claude Code adapter, **Codex desktop app** [primary Remote Control pairing path], compatible shell [ASSUMPTION: bash/zsh, macOS defaults — not yet enumerated by explicit compatibility test], outbound HTTPS) or **Optional/candidate** (Homebrew = install mechanism, Node.js = only if something actually needs it, **Codex CLI = secondary/diagnostic, required only for managed-host/SSH/devbox scenarios or adapter start/status/stop**, tmux = persistence candidate pending the Phase 6 spike, Docker = optional/future hardening).
- **FR-3** `doctor.sh` runs and reports even when dependencies are missing; a missing dependency blocks only the specific capability, never the diagnostic itself.
- **FR-4** `doctor.sh` detects provider update notices (e.g. "Update available: brew upgrade claude-code@latest") and records them as discovery findings; it never executes updates.
- **FR-5** A controlled update procedure (separate from `doctor.sh`) records the current version, checks changelog/compatibility, performs the update, re-verifies auth + Remote Control, and documents rollback if a regression appears.

### B. Repository and BMAD scaffold (Phase 1-2)
- **FR-6** The repository follows a BMAD-compatible structure (`AGENTS.md`, `CLAUDE.md`, `scripts/`, `config/`, `workspaces/`, `docs/`) recognized by Claude Code and Codex.
- **FR-7** Secrets are excluded from the repository from initialization (`.gitignore`/structure).

### C. Workspace model and isolation (Phase 7)
- **FR-8** The user can register a user-defined workspace with: stable id, name, authorized root path, allowed providers, permission configuration, non-sensitive metadata, enabled/disabled state.
- **FR-9** Registration validates the root path exists and is authorized before activation.
- **FR-10** `agentic-workstation` enforces verifiable **logical** isolation per workspace via canonical paths, boundary validation, path-traversal rejection, and detection of symlinks that escape the authorized root; it never mixes metadata, configuration, or commands across workspaces; every rejection is logged. Additional OS/provider-level enforcement must be detected and documented explicitly, never assumed.
- **FR-10A** Diagnostics report the effective isolation level per provider as `logical`, `provider_sandboxed`, `os_enforced`, or `unknown`.
- **FR-11** Any operation attempting to cross a workspace boundary is rejected with an explicit, auditable error that never reveals secrets.

### D. Adapter common contract (Phases 3-4)
- **FR-12** Each provider (Claude Code, Codex) is wrapped by an adapter implementing a common lifecycle contract: `doctor`, `start`, `status`, `stop`, `recover`.
- **FR-13** Each adapter reports one of: `available`, `not_installed`, `authentication_required`, `plan_not_supported`, `remote_control_unavailable`, `version_incompatible`, `network_unavailable`, `unknown_error`.
- **FR-14** The common contract covers only the basic session lifecycle; provider-specific capabilities and errors beyond that are preserved, never hidden or artificially unified.

### E. Session lifecycle (Phase 5)
- **FR-15** The user starts a session (provider + workspace) via a uniform command, producing local non-sensitive session metadata (`sessionId`, `provider`, `workspace`, `status`, `startedAt`).
- **FR-16** The user lists active sessions and their status via a uniform command.
- **FR-17** The user stops a session by id via a uniform command.
- **FR-18** For sessions configured as persistent, a documented recovery procedure of at most 3 steps exists after closing the terminal.
- **FR-19** Every session traces to exactly one provider and one workspace.
- **FR-30** The user can maintain at least 2 simultaneous sessions across different workspaces, with no collisions in IDs, metadata, working directories, or lifecycle commands. Same-provider concurrency is required only if the provider supports it; otherwise it is diagnosed, not forced.

### F. Remote Control (Phases 3-4)
- **FR-20** The Claude Code adapter invokes, supervises, and diagnoses the native Remote Control using only public, documented provider interfaces.
- **FR-21** The Codex adapter invokes, supervises, and diagnoses the native Remote Control using only public, documented interfaces — primarily the desktop app pairing flow (Settings → Connections → "Control this Mac or PC" → QR), with the documented CLI (`codex remote-control` / `start` / `pair` / `stop`) as the adapter's scripted entry point. Per-account/rollout availability is validated by the narrowed S1 spike (see §7); it is never assumed present.

> **[NOTE FOR PM]** S1 confirms Codex Remote Control *exists* and is documented; it does not confirm it is *enabled* for this specific account/workspace/rollout. Treat that gap as live risk until `doctor` reports `available` for Codex Remote Control on the validation Mac.

> **Note:** FR-22 was reclassified out of this FR set — see EQ-1 in §9, a provider-dependent mobile qualification scenario rather than a build requirement. Numbering continues at FR-23 to keep prior IDs stable.

- **FR-23** If a provider's Remote Control is unavailable, the adapter diagnoses and reports the specific blocking reason (per FR-13); it is never substituted with a custom-built alternative.
- **FR-32** Before enabling Remote Control, the user can view the external dependency involved, the authentication mechanism, and a link to the provider's applicable policy/documentation.

### G. Persistence (Phase 6)
- **FR-24** For each provider whose persistence is compatible, closing the terminal window does not terminate a session configured as persistent. The chosen mechanism must use a supported, documented interface, per provider. If a provider requires a foreground process or has restrictions, the adapter reports it as a limitation and never simulates a `running` state.
- **FR-24A** `status` detects dead processes and stale metadata, avoiding reporting nonexistent sessions as active.
- **FR-25** A documented recovery procedure exists after a Mac restart, even without guaranteed auto-restart.

### H. Minimal security (Phase 8)
- **FR-26** No provider or workspace credential is stored inside the repository, workspace configuration, or logs.
- **FR-27** `agentic-workstation` references credentials via a secure system mechanism rather than duplicating/exporting provider-managed tokens, and avoids reading/centralizing internal provider tokens unless indispensable. **"Indispensable" means:** no public, documented provider interface (CLI flag, status command, documented API) exposes the needed capability without directly handling the token — and that gap must be justified in an ADR before implementation, not asserted in code.
- **FR-28** Logs never contain tokens or secrets, verified as part of the security review.

> **Note:** FR-26/FR-27 state the *requirement*; the concrete *mechanism* (D2 — Keychain vs. provider-managed storage) is still an open spike resolved during Phase 8, not a settled implementation choice.
>
> **[NOTE FOR PM]** D2's outcome may change FR-27's implementation shape (e.g., if Claude Code/Codex already manage credentials securely enough that `agentic-workstation` needs zero direct token handling, FR-27's "unless indispensable" clause may end up unused in practice — that would be the best outcome, not a gap).

### I. Provider independence
- **FR-29** A failure, missing auth, or unavailable Remote Control in one provider never blocks starting, operating, or diagnosing the other provider.

### J. Compatibility
- **FR-31** `doctor` generates a compatibility/support matrix recording macOS version, architecture, provider versions, install method, and verified capabilities.

## 9. Mobile Qualification Scenario (provider-dependent, not a build requirement)

- **EQ-1** For each provider declared available, validate from the phone the flow: open session → request change → respond/approve action → run tests → review result/diff, where available. If any action is unavailable in a provider's mobile UI, log it as a limitation — it is never auto-converted into a feature `agentic-workstation` must build. For Codex specifically, qualification includes confirming the desktop-app-hosted QR pairing flow completes and the paired mobile session reaches the workspace's active session, exercised end-to-end by running one small BMAD story from the phone.

## 10. Non-Functional Requirements

- **NFR-1** (Security) Least privilege: file access restricted to the workspace's authorized root path (allowlist).
- **NFR-2** (Security) — **Deferred to Oracle Cloud PRD.** SSH key-only access is out of scope for this local-Mac PoC (native Remote Control is the access channel here); ID kept stable for future reactivation.
- **NFR-3** (Security) No silent bypass of command review / tool-approval prompts.
- **NFR-4** (Reliability) Session persistence survives terminal close; Mac sleep/suspend is documented as a known limitation, not resolved in this PoC.
- **NFR-5** (Performance) Guided setup ≤ 30 min post-prerequisites; session start ≤ 60s excluding provider auth/latency.
- **NFR-6** (Auditability) Isolation violations and adapter state transitions are logged locally, without secrets.
- **NFR-7** (Extensibility) The adapter contract allows adding a third provider later without redesigning the workspace/session model.
- **NFR-8** (Maintainability) Scripts stay simple and dependency-light (doctor/start/status/stop); no premature backend architecture in this PoC.
- **NFR-9** (Documentation) Installation and recovery are reproducible from documentation alone, verified via a clean-install test.
- **NFR-10** (Data minimization) Locally stored session metadata contains no sensitive data.
- **NFR-11** (Compatibility) The PoC is supported on the Mac used for validation. Other macOS versions/architectures are considered supported only after a successful run of the corresponding qualification suite on that machine. [ASSUMPTION: "the Mac used for validation" refers to the author's current machine; exact macOS version/build is not pinned in this PRD and will be captured by the Phase 0 discovery report, `docs/discovery/local-environment.md`.]
- **NFR-12** (Data-flow transparency) Documentation states what stays on the Mac versus what Anthropic or OpenAI may transmit/store via authentication, model usage, and Remote Control.

## 11. Isolation Acceptance Tests (traces to FR-10/FR-10A/FR-11)

1. Reject a request for `../workspace-b`.
2. Reject an absolute path outside the workspace.
3. Reject an internal symlink that escapes the workspace root.
4. Metadata separation verified across two simultaneous sessions.
5. A `workspace-a` session cannot operate on `workspace-b` via `agentic-workstation` commands.
6. Every rejection result distinguishes a wrapper-level block from a real provider/OS-level block.

## 12. Traceability

| Requirement group | Outcome / Metric | poc-plan Phase |
|---|---|---|
| A: FR-1–FR-5 | Metrics 9, 10 (partial) | Phase 0 |
| B: FR-6–FR-7 | Metric 8 (reproducible repo) | Phase 1-2 |
| C: FR-8–FR-11, FR-10A | Metrics 4, 6, 8, 11, 12 | Phase 7 |
| D: FR-12–FR-14 | Metric 5 (common contract) | Phase 3-4 |
| E: FR-15–FR-19, FR-30 | Metrics 1–3, 4, 5, 11 | Phase 5 |
| F: FR-20, FR-21, FR-23, FR-32 | Metrics 1, 4-5, 10 (qualification) | Phase 3-4 |
| EQ-1 | Provider-dependent mobile qualification | Phase 3-4 |
| G: FR-24, FR-24A, FR-25 | Metric 3, reliability | Phase 6 |
| H: FR-26–FR-28 | Metric 7, security | Phase 8 |
| I: FR-29 | Metric 10 | Cross-cutting |
| J: FR-31 | Metric 9 | Cross-cutting |
| NFR-1, NFR-3, NFR-6 | Security posture | Phase 8 |
| NFR-2 | Deferred | Oracle Cloud PRD |
| NFR-4, NFR-9 | Metric 3, 8 | Phase 6 |
| NFR-5 | Metrics 1-2 | Cross-cutting |
| NFR-7, NFR-8 | Provider-neutral architecture vision | Architecture |
| NFR-10 | Metric 7 | Phase 5/8 |
| NFR-11 | Compatibility scoping | Phase 0 |
| NFR-12 | Trust/transparency | Phase 3-4/8 |

## 13. Note on Threat Modeling

`poc-plan.md` Phase 2 lists a "basic threat model" among its BMAD artifacts, alongside PRD/architecture/epics/ADRs. That threat model is produced during `bmad-architecture` (it reasons over the adapter/isolation/persistence design this PRD requires, not over product scope), not authored as part of this PRD. NFR-1, NFR-6, and the isolation acceptance tests in §11 are this PRD's security-relevant inputs to that future threat model.

## 14. Open Questions

- Exact mechanism for D2 (Keychain vs. provider-managed credential storage) — resolved during Phase 8 spike, not blocking PRD finalization.
- Exact persistence mechanism per provider (S3) — resolved during Phase 6 spike.
- Whether Codex Remote Control is **enabled** for this specific account/workspace/rollout (S1, narrowed from "does it exist" to a local validation spike since the capability itself is now confirmed documented — see §7 Sources) — resolved during Phase 4 spike; PoC proceeds regardless of outcome per the provider-dependent qualification model in §5.
