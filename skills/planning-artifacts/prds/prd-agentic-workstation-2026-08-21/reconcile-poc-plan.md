---
title: Reconcile — poc-plan.md vs PRD (Phases 0-8)
input: docs/product/poc-plan.md
compared_against: skills/planning-artifacts/prds/prd-agentic-workstation-2026-08-21/prd.md
scope: poc-plan.md Phases 0-8 only (Phases 9-10 intentionally deferred, ADR list and Naming intentionally excluded)
---

# Reconciliation: poc-plan.md → prd.md

## Genuine content gaps found

1. **Phase 0 — SSH configuration inspection.** poc-plan.md lists "Inspeccionar configuración SSH" as a discovery task. The PRD's discovery FRs (FR-1–FR-5) cover macOS/architecture/shell/tool inspection and dependency classification, but do not mention inspecting SSH config as part of `doctor.sh`'s output. Not represented in any FR, journey step, or NFR.

2. **Phase 0 — open ports inspection.** poc-plan.md lists "Revisar puertos abiertos" as a discovery task. No FR, metric, or NFR in the PRD references port inspection as part of discovery output.

3. **Phase 0 — locating available projects/repos.** poc-plan.md lists "Localizar los proyectos disponibles" as a discovery task. The PRD's discovery scope (FR-1–FR-5) is about tools/dependencies/versions, not about enumerating candidate repositories/projects on the Mac. No corresponding FR.

4. **Phase 2 — basic threat model.** poc-plan.md's Phase 2 deliverables include "Modelo de amenazas básico" as an artifact to produce alongside the PRD/architecture/epics/stories. This is distinct from the ADR list (already excluded per instructions) and from NFR security content (which states security requirements, not a threat-modeling deliverable/process). No FR or section in the PRD calls for producing a threat model artifact.

5. **Phase 4 — validating a small BMAD story end-to-end via Codex.** poc-plan.md's Phase 4 acceptance criteria includes "Ejecutar una historia BMAD pequeña" as a validation step for Codex Remote Control (running an actual BMAD story through the remote session, beyond diff/test review). The PRD's EQ-1 mobile qualification scenario covers open/request-change/approve/test/diff-review generically, but doesn't specifically call for exercising a BMAD story as part of qualification — a minor but concrete acceptance-criterion detail not textually present anywhere in the PRD.

## Notes
- Phases 9-10 content not flagged (intentional deferral, already documented in PRD §4 Scope).
- ADR-001..007 list and "Naming" section not flagged (architecture/branding concerns, not PRD content).
