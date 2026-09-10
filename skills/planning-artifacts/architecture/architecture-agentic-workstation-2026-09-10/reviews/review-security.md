# Review — security lens, public repo (inline, 2026-09-10)

- Secrets/identity: no ACL file, no auth keys, no node names committed (AD-2, AD-3, AD-7) ✔. `SSH_USER` lives only in gitignored `config/local.env` ✔.
- Claude transcripts (`~/.claude/projects/...`) sit on the host outside any workspace repo — added one sentence to AD-7 so a builder never symlinks them into the tree.
- Permission mode: `--permission-mode default`, no bypass, no `--add-dir` (AD-6) ✔. Runtime guard: refuse `SSH_USER=root`.
- Fallback sshd hardening set matches addendum baseline (AD-3) ✔; reachability via tailnet ACL rather than `ListenAddress` pinning avoids a silent public bind if the tailnet IP changes — documented as a note in `fallback-openssh.md` (Deferred → docs).
- Check-mode re-auth needs a browser URL on headless/WSL clients: docs item, not an AD.
- `stop.sh` is destructive to a running agent session: require the explicit session name, never a wildcard — added to AD-4 rule.
- CI: gitleaks-action is the hard gate; pre-commit is best-effort per machine (AD-7 already says CI red on findings) ✔.

Verdict: **PASS** after the two one-line additions.
