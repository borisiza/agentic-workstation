# Plan PoC: Agentic Development OS local

## Objetivo

Construir en un Mac una estación de desarrollo agentic disponible remotamente desde el celular, capaz de ejecutar:

- Claude Code.
- Codex.
- Proyectos independientes.
- BMAD.
- Remote Control.
- Autenticación inicial.
- Sesiones persistentes.
- Controles básicos de seguridad.

La PoC termina cuando puedas iniciar y controlar Claude Code y Codex desde el teléfono trabajando sobre un repositorio real.

## Fase 0: descubrimiento

Codex debe inspeccionar el Mac sin modificarlo.

### Tareas
- Detectar arquitectura: Intel o Apple Silicon.
- Revisar macOS y herramientas instaladas.
- Revisar versiones de Claude Code y Codex.
- Detectar Homebrew, Node.js, Git, Docker y tmux.
- Inspeccionar configuración SSH.
- Revisar puertos abiertos.
- Localizar los proyectos disponibles.
- No mostrar secretos ni credenciales.

### Entregable
- `docs/discovery/local-environment.md`

### Criterio de aceptación
Tenemos un inventario reproducible y una lista de dependencias faltantes.

## Fase 1: repositorio de la PoC

Proyecto: **agentic-workstation** (nombre de producto futuro: Agentic Development OS).

### Estructura

```
agentic-workstation/
├── .claude/
│   ├── settings.json
│   └── commands/
├── .codex/
├── .bmad-core/
├── apps/
│   └── control-plane/
├── config/
│   ├── agents/
│   ├── workspaces/
│   └── permissions/
├── docs/
│   ├── architecture/
│   ├── discovery/
│   ├── product/
│   └── stories/
├── scripts/
│   ├── doctor.sh
│   ├── start-claude.sh
│   ├── start-codex.sh
│   ├── status.sh
│   └── stop.sh
├── workspaces/
├── AGENTS.md
├── CLAUDE.md
├── README.md
└── .gitignore
```

### Criterio de aceptación
- Repositorio Git inicializado.
- Secretos excluidos.
- README.md explica la PoC.
- Claude Code y Codex reconocen las instrucciones del proyecto.

## Fase 2: arquitectura BMAD

Generar los artefactos antes de implementar automatizaciones.

### Artefactos
- Product brief.
- PRD de la PoC.
- Arquitectura.
- Modelo de amenazas básico.
- Épicas.
- Historias de usuario.
- ADR iniciales.

### ADR necesarias
- ADR-001: Mac como runtime inicial
- ADR-002: Remote Control como canal remoto
- ADR-003: Procesos persistentes
- ADR-004: Separación de workspaces
- ADR-005: Gestión de secretos
- ADR-006: Evolución hacia Oracle Cloud
- ADR-007: Firebase Identity Platform

### Criterio de aceptación
Cada decisión debe distinguir:
- Decisión para la PoC.
- Limitaciones.
- Alternativa descartada.
- Evolución para producción.

## Fase 3: Claude Code Remote Control

### Tareas
- Instalar o actualizar Claude Code.
- Autenticar con la cuenta personal.
- Crear un workspace de prueba.
- Activar Remote Control.
- Nombrar claramente la sesión.
- Validar acceso desde Claude móvil.
- Validar ejecución de comandos y cambios Git.
- Comprobar reconexión.

### Comando esperado
```
claude --remote-control "Mac Boris - PoC"
```

### Criterio de aceptación
Desde el celular puedes: abrir la sesión, leer archivos, solicitar una modificación, aprobar una acción, ejecutar tests, ver el cambio en Git.

## Fase 4: Codex Remote Control

### Tareas
- Instalar o actualizar Codex.
- Autenticar con ChatGPT.
- Iniciar Remote Control.
- Emparejar el celular.
- Abrir el mismo workspace de prueba.
- Validar permisos y sandbox.
- Ejecutar una historia BMAD pequeña.

### Comando esperado
```
codex remote-control start
```

### Criterio de aceptación
Desde el celular puedes: seleccionar el Mac, continuar una sesión, responder preguntas, aprobar herramientas, revisar diffs, ver resultados de pruebas.

## Fase 5: administrador local de sesiones

Crear scripts simples; todavía no construir un backend complejo.

### Funciones
```
./scripts/doctor.sh
./scripts/start-claude.sh workspace-id
./scripts/start-codex.sh workspace-id
./scripts/status.sh
./scripts/stop.sh session-id
```

Cada sesión debe registrar únicamente metadatos no sensibles:

```json
{
  "sessionId": "session-001",
  "provider": "claude",
  "workspace": "poc-project",
  "status": "running",
  "startedAt": "ISO-8601"
}
```

### Criterio de aceptación
Podemos iniciar, listar y detener sesiones sin recordar comandos internos.

## Fase 6: persistencia 24/7 local

Primero evaluar los mecanismos nativos de cada producto. Usar tmux solamente cuando resulte necesario.

### Tareas
- Determinar qué daemon ofrece Claude Code.
- Determinar qué daemon ofrece Codex.
- Crear servicios launchd cuando corresponda.
- Reiniciar servicios después de cerrar sesión.
- Definir política después de reiniciar el Mac.
- Evitar ejecución con permisos de administrador.

### Criterio de aceptación
- Cerrar la terminal no mata el servicio.
- La suspensión del Mac se documenta como limitación.
- Después de reiniciar existe un procedimiento claro de recuperación.
- Los logs permiten diagnosticar fallos sin exponer secretos.

## Fase 7: aislamiento de workspaces

### Modelo inicial
```
workspaces/
├── personal/
├── publea/
└── sandbox/
```

Cada workspace tendrá: ruta autorizada, repositorios permitidos, agentes disponibles, MCP permitidos, nivel de permisos, variables requeridas, proveedor (Claude, Codex o ambos).

### Criterio de aceptación
Una sesión iniciada para sandbox no debe operar accidentalmente sobre publea.

## Fase 8: seguridad mínima

### Controles
- Nada de claves dentro del repositorio.
- Uso de macOS Keychain o variables inyectadas.
- Permisos de archivos restrictivos.
- SSH exclusivamente con llaves.
- Revisión de comandos con bypass deshabilitado.
- Logs sin tokens.
- Allowlist de directorios.
- Backups mediante Git remoto.
- Revisión de dependencias.

### Criterio de aceptación
Ejecutar una revisión de seguridad y documentar riesgos residuales.

## Fase 9: portal local con Firebase

Esta fase comienza únicamente después de que Remote Control funcione bien.

### Primera versión
- Flutter Web o interfaz mínima.
- Login con Firebase Authentication.
- Google Sign-In.
- Registro de usuarios.
- Lista de workspaces.
- Lista de sesiones.
- Botones para iniciar y detener sesiones.
- Backend local que verifica Firebase ID Tokens.

### Fuera del alcance inicial
SAML, OIDC empresarial, multi-tenancy completo, facturación, Kubernetes, varios clientes reales.

### Criterio de aceptación
Un usuario autenticado puede visualizar solo sus workspaces y solicitar una sesión mediante el control plane.

## Fase 10: migración a Oracle

Cuando la PoC local esté validada:

- Crear Oracle A1 ARM64.
- Repetir doctor.
- Instalar el runtime.
- Migrar configuraciones, no credenciales.
- Configurar Tailscale.
- Ejecutar Claude y Codex.
- Validar Remote Control desde el celular.
- Configurar backups y monitoreo.
- Comparar ARM64 con Apple Silicon.

## Orden de historias

| ID | Historia |
|----|----------|
| POC-001 | Inventariar el Mac |
| POC-002 | Crear repositorio base |
| POC-003 | Generar arquitectura BMAD |
| POC-004 | Conectar Claude Remote Control |
| POC-005 | Conectar Codex Remote Control |
| POC-006 | Administrar sesiones |
| POC-007 | Persistir procesos |
| POC-008 | Aislar workspaces |
| POC-009 | Revisar seguridad |
| POC-010 | Incorporar Firebase |
| POC-011 | Preparar migración a Oracle |

## Naming

- Repositorio actual: `agentic-workstation`.
- Producto futuro: Agentic Development OS.
- Componente de administración futuro: `agentic-control-plane`.
- Descripción GitHub: "Remote development workstation powered by Claude Code, Codex, BMAD and secure multi-workspace orchestration."

## Nota de ejecución

La primera iteración (POC-001) se detiene después del diagnóstico: inspección sin instalar, actualizar ni eliminar nada, sin imprimir tokens/claves/credenciales, entregando `docs/discovery/local-environment.md` y proponiendo POC-002 sin ejecutarla.
