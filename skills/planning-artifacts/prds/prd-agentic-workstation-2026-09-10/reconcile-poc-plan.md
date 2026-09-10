# Reconciliation — poc-plan.md vs PRD + addendum

Input: `skills/planning-artifacts/poc-plan.md` (285 líneas).
Comparado contra: `prd.md` + `addendum.md` de `prd-agentic-workstation-2026-09-10`.

Scoping ya decidido por el owner (NO son gaps): celular/Remote Control (Fase 3 del poc-plan),
Codex (Fase 4), Firebase/portal (Fase 9), Oracle (Fase 10), workspaces aislados (Fase 7) — todo
correctamente reflejado en el roadmap del PRD y en la tabla de mapping del addendum.

## Gaps reales (ideas perdidas, ni en PRD ni en addendum, ni cubiertas por scoping)

1. **Fase 8 — controles de seguridad no absorbidos en FR11–13/NFR1, pese a que el addendum dice
   "8's controls absorbed":**
   - "Permisos de archivos restrictivos" (file perms) — sin FR ni NFR equivalente.
   - "Allowlist de directorios" — el poc-plan lo pone en Fase 8 (seguridad mínima, no en Fase 7
     de workspaces), o sea aplicaba también al MVP de un solo workspace; el PRD no tiene ningún FR
     que restrinja a qué directorios puede tocar la sesión SSH/Claude Code.
   - "Backups mediante Git remoto" — no aparece como requisito ni NFR (aunque el repo ya es Git,
     no hay criterio de aceptación tipo "el trabajo sobrevive si se pierde el Mac").
   - "Revisión de dependencias" — sin mención (ni siquiera como roadmap).
   - "Uso de macOS Keychain o variables inyectadas" — el PRD solo dice "config/local.env
     gitignored" (NFR4); no menciona Keychain como opción evaluada, que era explícita en el poc-plan.

2. **Fase 5 — naming de sesión ("Nombrar claramente la sesión")**: era un criterio de aceptación
   explícito de la Fase 3 del poc-plan ("Nombrar claramente la sesión" + comando esperado
   `claude --remote-control "Mac Boris - PoC"` con nombre legible). El PRD (FR6–FR8) especifica
   el modelo de sesión (id, workspace, status, startedAt) pero no exige que el id/nombre de sesión
   sea legible/identificable por humanos — se perdió el criterio cualitativo de naming, no solo
   el canal (phone) que sí quedó correctamente diferido.

3. **Criterio de aceptación cualitativo de Fase 3 — "aprobar una acción" desde el canal remoto**:
   el poc-plan pedía explícitamente poder aprobar acciones (permission prompts) de punta a punta
   dentro del flujo de demo. El PRD lo cubre indirectamente vía FR5 ("approvals happen in the
   remote terminal") — esto SÍ está cubierto, no es gap; se incluye acá solo para dejar constancia
   de que se verificó y no falta.

4. **Doctor.sh — alcance reducido sin nota explícita**: poc-plan Fase 0 pedía que doctor detecte
   Homebrew, Node.js, Git, Docker y tmux, y revisar SSH/puertos. El PRD (FR9) reduce doctor.sh a
   "ssh, tmux, claude, git" sin Docker/Homebrew/Node — razonable para el MVP re-enfocado, pero el
   addendum no documenta la reducción de alcance (solo dice "0 discovery, 1 repo: done/absorbed",
   que no es exacto — Fase 0 no está "absorbida", su entregable `docs/discovery/` quedó fuera de
   git por hygiene, y su función de detección de dependencias quedó recortada en doctor.sh sin que
   quede explícito en ningún artefacto).

## Resumen

Input: `skills/planning-artifacts/poc-plan.md`
4 gaps concretos — todos dentro de Fase 8 (seguridad, 4 sub-controles) y Fase 5 (naming de sesión),
más una nota de alcance no documentada en Fase 0/doctor.sh.
Archivo: `skills/planning-artifacts/prds/prd-agentic-workstation-2026-09-10/reconcile-poc-plan.md`
