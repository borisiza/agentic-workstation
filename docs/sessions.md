# Reconnect and resume a session

A `claude-<workspace>` session survives a dropped link because it lives in a
persistent tmux session on the *host*, not in the SSH/`tailscale ssh`
connection to it. This guide covers what to do when the link drops:
reattaching, detaching on purpose, recovering after the host itself reboots,
and where the underlying Claude Code transcript lives. Before using this
guide, first enroll the host (one of [node-linux.md](node-linux.md),
[node-macos.md](node-macos.md), [node-wsl.md](node-wsl.md)) and start a
session on it from a client via [node-client.md](node-client.md)'s
`connect.sh <node> <workspace>`.

## Conventions

- `<node>` and `<workspace>` are placeholders — never write a real hostname,
  tailnet IP, or workspace inventory into a doc, config, or commit in this
  repo.
- Every command below is copy-pasteable as written (after you substitute your
  own `<node>`/`<workspace>`).

## 1. Reattach after a dropped link

From the client, re-run the exact same command that started the session:

```sh
scripts/connect.sh <node> <workspace>
```

There is no separate "reconnect" command. `connect.sh` execs `tailscale ssh`
straight into `start-claude.sh <workspace>` on the host, and `start-claude.sh`
itself execs:

```sh
tmux new -A -s claude-<workspace> -- ...
```

`-A` makes this attach-or-create: if `claude-<workspace>` is still running on
the host (it is — a dropped link never kills it, only `stop.sh` does), the
same re-run reattaches to it instead of starting a second session. Scrollback
and conversation context are exactly as you left them, because the tmux
session and the Claude Code process inside it never stopped — only the
transport between you and them did. This whole round trip (re-run `tailscale
ssh`, tmux redraw the pane) is expected to land well under a minute.

If you (or someone else) ran `scripts/stop.sh <workspace>` since you last
detached, this reattach starts a brand-new session instead — `stop.sh` is the
one thing that actually ends `claude-<workspace>`, so there is nothing left
to reattach to.

## 2. Detach on purpose

The tmux default detach key is `Ctrl-b` then `d`. Detaching leaves the
session running on the host, exactly like a dropped link does — the only
difference is you chose it. There is nothing else to do to "prepare" for a
drop: closing the terminal window, sleeping the client laptop, or losing the
network all leave the host-side session running, same as an explicit detach.

## 3. Both directions at once

Node A can run a session hosted on B (`connect.sh B <workspace>` from A)
while node B independently runs a session hosted on A
(`connect.sh A <other-workspace>` from B) — nothing about running one
direction requires or disturbs the other. Each host owns exactly one tmux
server, and `claude-<workspace>` lives entirely on the host side of a given
`connect.sh` call; the two sessions never share state, and `stop.sh
<workspace>` on one host only ever targets that host's own tmux server by
exact session name (no wildcard, no `kill-server`). To see both running
independently, run `scripts/status.sh` on each host — it lists that host's
own `claude-*` sessions from live tmux state.

## 4. Install the optional tmux config

[`config/tmux.conf.example`](../config/tmux.conf.example) sets a large
`history-limit` (so a long-running conversation's scrollback isn't trimmed)
and `mouse on` (click to select a pane, scroll wheel to scroll back, drag to
resize). Both settings are global (`-g`) — they apply to every tmux session
on the host, not only `claude-<workspace>` ones. It is not read by any
script — install it on the host only if you want it:

```sh
cp config/tmux.conf.example ~/.tmux.conf
tmux source-file ~/.tmux.conf   # reload it into an already-running tmux server
```

A brand-new tmux server picks it up automatically on next start; an
already-running one needs the `source-file` reload (or just let it apply the
next time the host reboots and `tmux new` starts fresh). With mouse mode on,
selecting text for copy needs a modifier (e.g. hold `Shift` while dragging on
most terminals) instead of a plain drag.

## Caveat: host reboot — recovery is manual, not automated

A host reboot kills the tmux *server* itself, which is a different failure
mode than a dropped link: there is no tmux session left to attach to.
Recovery is a documented manual step, not something any script performs for
you:

```sh
scripts/start-claude.sh <workspace>
```

This creates a fresh `claude-<workspace>` tmux session (the old one is gone
with the server) and launches a brand-new Claude Code conversation directly
in it, leaving no shell in that window to type further commands into. To
resume the *previous* conversation instead, open a second window inside that
same tmux session (`Ctrl-b` then `c`) and run:

```sh
claude --resume claude-<workspace>
```

there. Claude Code's own on-disk history for that session name is what
actually carries the conversation forward — the tmux scrollback from before
the reboot is gone, but the conversation context is not. This is deliberately
not scripted: automating a host reboot recovery is out of scope for this
story.

## Caveat: tailscaled restart and manual recovery

If `tailscaled` itself restarts or crashes on the host while you're mid-session
(not the same as a dropped link — this is the tailnet daemon, not the tmux
session), your `tailscale ssh` connection can drop and won't reconnect until
`tailscaled` is back up and the host has rejoined the tailnet. Once it has,
step 1 above (re-run `connect.sh`) is all you need — the tmux session was
never touched. If `tailscaled` doesn't come back on its own, each host guide
has the full diagnosis-and-recovery path for that platform, including the
`tailscale serve --tcp 2222 22` local-sshd shim as a last resort:

- [node-macos.md — Caveat: tailscaled restart and manual recovery](node-macos.md#caveat-tailscaled-restart-and-manual-recovery)
- [node-linux.md — Caveat: tailscaled restart and manual recovery](node-linux.md#caveat-tailscaled-restart-and-manual-recovery)
- [node-wsl.md — Caveat: tailscaled restart and manual recovery](node-wsl.md#caveat-tailscaled-restart-and-manual-recovery)

## Where transcripts live

Claude Code's own transcripts for a session stay in `~/.claude/` on the
*host* — never inside the workspace directory and never inside this repo.
They are what `claude --resume claude-<workspace>` reads from after a host
reboot; nothing in this repo copies, mirrors, or backs them up.

## Verification

This doc adds no new script or command of its own — every command above is
`connect.sh`, `start-claude.sh`, `stop.sh`, or plain `tmux`/`claude`, already
covered by those scripts' own `--check` self-tests (2.1-2.3). What's specific
to this doc was checked by hand: every cross-reference above resolves to a
real heading in [node-macos.md](node-macos.md) / [node-linux.md](node-linux.md) /
[node-wsl.md](node-wsl.md), and
[`config/tmux.conf.example`](../config/tmux.conf.example) was read
line-by-line against `history-limit`/`mouse` tmux syntax. The end-to-end
reconnect-under-a-minute claim and the both-directions coexistence claim
still require running the M1 protocol (see epics.md Story 2.4) on two real
tailnet nodes; see this story's spec file for that result.
