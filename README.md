# agentic-workstation

A multi-node mesh for running agentic CLIs (Claude Code and friends) across your own machines, reachable and controllable from wherever you are.

## Public-repo rules

This repository is public. Nothing that identifies a specific host, network, or person may ever be committed here.

- **Placeholders only.** Docs, configs, and scripts reference machines and locations using generic placeholders — `<node>`, `<user>`, `<workspace>`, `<distro>` — never a real hostname, IP address, tailnet name, or username.
- **No host list.** Never commit an inventory of real machine names, addresses, or mesh topology.
- **Secrets stay untracked.** Any personal value (a real hostname, key, or token) belongs only in `config/local.env`, which is gitignored and must never be committed.

## Hygiene gates

Every commit and every push/PR is checked for secrets and shell-script issues:

- **Local:** `pre-commit install` wires up a `gitleaks` hook (`.pre-commit-config.yaml`) that scans staged changes before each commit.
- **CI:** `.github/workflows/hygiene.yml` runs `shellcheck` over `scripts/*.sh` and `gitleaks` over the full git history on every push and pull request. The job fails on any finding.

The `.gitleaks.toml` allowlist only exempts the literal placeholder tokens above — it never allowlists a real value.
