# Review — Stack versions verified current (inline, 2026-09-10)

| Row | Claimed | Verified against | Status |
| --- | --- | --- | --- |
| Tailscale | 1.102.3 | github.com/tailscale/tailscale/releases (latest), formulae.brew.sh/formula/tailscale (1.102.3) | ✔ |
| tmux | 3.7c | github.com/tmux/tmux/releases (3.7c latest, 3.8-rc pre-release) | ✔ |
| Claude Code | ≥ 2.1.257 | code.claude.com/docs (sessions, agent-view cite 2.1.257 as newest gated feature); native installer auto-updates | ✔ floor, not a pin — [ASSUMPTION] logged |
| gitleaks | 8.30.1 | github.com/gitleaks/gitleaks/releases (2026-03-21) | ✔ |
| shellcheck | 0.11.0 | github.com/koalaman/shellcheck/releases (2025-08-04, still latest) | ✔ |
| WSL | ≥ 2.4.4 | microsoft/WSL discussion #9245 (instanceIdleTimeout added in 2.4.4); MS Learn wsl-config page lists vmIdleTimeout only | ⚠ community-sourced — marked [ASSUMPTION] in spine |
| bash | 3.2 target | macOS ships 3.2; scripts must also run on 5.x | ✔ |
| mosh (Deferred) | 1.4.0 | github.com/mobile-shell/mosh/releases (2024-10-27) | ✔ (not in Stack) |

Verdict: **PASS** with one [ASSUMPTION] tag added (WSL instanceIdleTimeout).
