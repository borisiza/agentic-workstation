# Review — rubric walk + adversarial "two builders diverge" (inline, 2026-09-10)

Mode: inline (Agent subagents blocked by the project hook in this build — see memlog event).

## Findings (severity · location · what diverges)

1. **high** · AD-1 · Role semantics are declared but not enforced: builder A lets `connect.sh` run on a `host`-only node, builder B refuses. → Rule added: client verbs require `client|both`, host verbs require `host|both`; others exit 2.
2. **high** · AD-8 / Structural Seed · `connect.sh` invokes `start-claude.sh` "remotely" but nothing fixes *where* the repo lives on the host; non-interactive `tailscale ssh` does not source the login profile, so PATH lookups diverge. → Convention added: repo path is `$HOME/agentic-workstation` on every node; remote command uses the absolute path.
3. **high** · AD-3 · FR18 fallback selection: with no registry (AD-1/AD-2) a client cannot know a host is a fallback host. Builder A invents a per-host client list; builder B probes. → Rule added: `connect.sh --fallback <node> <workspace>` is explicit; it uses the client's own untracked `~/.ssh/config` entry; no probing, no list.
4. **medium** · Conventions · `<workspace>` → path resolution unspecified (`$WORKSPACES_DIR/<workspace>` vs absolute path from the client). → Convention added: host resolves `$WORKSPACES_DIR/<workspace>`; must already exist; scripts never create it.
5. **low** · AD-4 · `tailscale ssh` needs a TTY for tmux; add `-t` — implementation detail, noted in the sequence diagram command only.
6. **low** · AD-6 · "Tailscale SSH users must not be root" belongs with AD-3's auth rule; kept in AD-6 as the runtime guard (script refuses `SSH_USER=root`). No change.

Rubric: paradigm named ✔ · ADs have Binds/Prevents/Rule ✔ · dependency diagram is a rule ✔ · Deferred present ✔ · no rationale leaked into spine ✔ (rationale in memlog) · placeholders 0 (lint) ✔.

Verdict after fixes: **PASS**.
