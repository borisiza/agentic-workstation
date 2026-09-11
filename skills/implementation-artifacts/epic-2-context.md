# Epic 2 Context: Run and resume Claude Code on any host from any node

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic delivers the actual remote-development workflow the mesh exists for: from any client node, one command lands the user in Claude Code inside a chosen workspace on a host, running in the project's normal permission mode. The session lives inside a persistent terminal multiplexer on the host so it survives a dropped link, terminal close, or lid-close; it can be listed, reattached with scrollback intact, and stopped precisely by name — and sessions started in both directions between two nodes coexist without colliding. It builds directly on Epic 1 (role config and tailnet membership already working) and is itself a prerequisite for Epic 3's OpenSSH fallback transport.

## Stories

- Story 2.1: Start Claude Code in a persistent tmux session on the host
- Story 2.2: List and stop workspace sessions on the host
- Story 2.3: Connect from a client to a host workspace with one command
- Story 2.4: Survive a dropped link and resume within a minute, in both directions

## Requirements & Constraints

- One command on a client reaches a chosen host and workspace and lands the user in Claude Code; the equivalent host-side command exists for local/direct use.
- Claude Code always runs in normal permission mode; no permission-bypass flag is ever used, and approvals happen in the attached terminal.
- A session is confined to its own workspace directory and must never reach sibling workspaces.
- Sessions run inside a persistent multiplexer so a dropped connection never kills the underlying process; reattaching restores the running session with scrollback intact.
- Sessions are namespaced per host and per workspace so simultaneous sessions started in both directions (A→B and B→A) never collide with each other.
- Listing sessions must work from live multiplexer state alone (no separate state file) and must show, per session, the workspace name, attached/detached status, and creation time; zero sessions is a normal, successful result.
- Stopping a session must target exactly one named session — never a wildcard or an action that could affect other sessions on the same host.
- Discovering reachable hosts (no target given) must happen at runtime from the tailnet's own live status, never from a persisted or committed host list.
- A network-drop reconnection must fully restore session state (scrollback and conversation context) in under 60 seconds; anything slower or lossier is a defect, not an accepted limitation.
- Scope boundary: this epic guarantees survive-disconnect, not survive-reboot. Recovery after the host itself reboots (multiplexer server gone) is a documented manual step, not an automated one.
- Sessions run as the login user only; a client must never be able to request or fall back to a root session on the host.
- Workspace names are restricted to safe characters and must already exist; no script in this epic creates a workspace directory.
- Every script in this epic exposes a side-effect-free self-test aggregated by the host readiness check, and follows the same portable-bash constraints as the rest of the project (bash 3.2 compatible, shellcheck-clean, no `jq`/Python).
- No script output may leak tokens, node names, or tailnet IPs.

## Technical Decisions

- Persistence is tmux, exclusively. Claude Code's own resume/daemon behavior is recovery-only, used solely to re-establish a session after the host's multiplexer server itself is gone (reboot) — it is never relied on for live continuity across a dropped link.
- Session identity contract: exactly one tmux session per workspace per host, created with idempotent attach-or-create semantics, so re-running the same start/connect command is always safe whether or not a session already exists.
- The Claude Code process inside the session is launched with a session name matching the tmux session name, working directory pinned to the workspace, and normal permission mode — never with a privilege-bypass flag or an extra-directory flag.
- The client-to-host flow chains the tailnet's identity-authenticated transport straight into the host-side start command, invoked by absolute path (the remote non-interactive shell does not source a login profile).
- Only the stop verb may terminate a session, and only the one session named on its command line — never a wildcard, never a full-server kill — so unrelated sessions on the same host are never at risk.
- Host discovery at connect time is derived by parsing the tailnet's own live status output as plain text; nothing is cached or committed.
- Client-side keepalive and multiplexer tuning (e.g. connection keepalive interval/count, scrollback size, mouse support) ship as example/template config, not hardcoded into scripts.
- Recovery after a host reboot is documented as a manual re-resume step and is explicitly outside the automated, timed reconnection guarantee.

## Cross-Story Dependencies

- Story 2.1 establishes the host-side session contract (naming, launch flags, attach-or-create) that Story 2.2's list/stop and Story 2.3's client connect both build on.
- Story 2.3 depends on Story 2.1 existing on the host, since the client command's job is to invoke it remotely.
- Story 2.4 doesn't add new scripts; it verifies the persistence and no-collision guarantees built by 2.1–2.3 hold end-to-end across two real nodes in both directions.
- This epic depends on Epic 1 for role configuration and tailnet membership already being in place. Epic 3's OpenSSH fallback depends on this epic's client connect command to add an alternate transport.
