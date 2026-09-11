# agentic-workstation

A multi-node mesh for running agentic CLIs (Claude Code and friends) across your own machines, reachable and controllable from wherever you are.

## What this is

Every machine you enroll — laptop, desktop, WSL distro — is a **node** running
this same repo. Nodes join a private [Tailscale](https://tailscale.com) tailnet
and address each other only by tailnet identity: no public ports, no port
forwards, no committed host list. A node's **role** (`host`, `client`, or
`both`) is local, untracked state set in `config/local.env` — nothing in the
repo names or lists any real machine. From a client node, one command opens a
shell on a host over `tailscale ssh`; on the host, that shell attaches to a
persistent `tmux` session running Claude Code, so a dropped connection never
kills the session.

## The four-layer model

A connection from one node to another is a strict stack of four independent
layers. Each layer keeps working even if the layer above it dies (a dropped
SSH connection doesn't kill the `tmux` session; a restarted `tailscaled` doesn't
kill the tailnet).

| Layer | Owner | Lives in |
| --- | --- | --- |
| L1 Network + identity | Tailscale tailnet (MagicDNS, ACL) | outside the repo (tailnet admin console) |
| L2 Transport + auth | Tailscale SSH (primary) / OpenSSH-over-tailnet (fallback) | `scripts/connect.sh`, `scripts/enroll.sh` |
| L3 Persistence | tmux server per host, one session per workspace | `scripts/start-claude.sh`, `status.sh`, `stop.sh` |
| L4 Agent | Claude Code interactive session in a workspace | inside the tmux session |

Only L1 (the tailnet itself) and `doctor.sh` (role/readiness, spanning L2-L4)
exist today — `connect.sh`, `enroll.sh`, `start-claude.sh`, `status.sh`, and
`stop.sh` are this epic's Epic 2/3 build-out targets, named here because the
repo layout mirrors these layers from the start.

## Prerequisites

Before enrolling any node, you need:

- A [Tailscale](https://tailscale.com) account and tailnet you control, and
  your tailnet identity to sign in with (the enrollment guides prompt for this
  — no auth key or ACL policy file is ever committed to this repo).
- `git`, to clone this repo onto the machine you're enrolling.
- For a **host** node: `tmux` and the [Claude Code CLI](https://docs.claude.com/en/docs/claude-code/setup)
  (each host guide below installs both) and a directory to hold per-project
  workspaces (`$HOME/workspaces` by default).
- For any **Windows** node (WSL2 host or WSL-as-client): WSL2 itself, already
  installed and set as default (`wsl --install`, which may require a reboot)
  — the node guides below assume this is already in place.
- Regular-user access — never run any script or guide step as `root`
  (or Administrator on Windows).

Each node guide below is self-contained and ends by running `./scripts/doctor.sh`,
the single source of truth for "is this node ready" — it checks the tools,
tailnet membership, and role-specific requirements above and reports
`PASS`/`FAIL`/`SKIP` per check, never guessing.

## Pick your node type

| Node type | What it does | Guide |
| --- | --- | --- |
| Linux host | Joins the tailnet as a Tailscale SSH host that can run Claude Code sessions | [docs/node-linux.md](docs/node-linux.md) |
| macOS host | Same, via Homebrew's open-source `tailscaled` (replaces the GUI app) | [docs/node-macos.md](docs/node-macos.md) |
| Windows host (via WSL2) | A WSL2 distro joins the tailnet as its own host node | [docs/node-wsl.md](docs/node-wsl.md) |
| Client-only node (macOS, native Windows, or WSL) | Reaches into the mesh (`tailscale ssh` into a host) without hosting sessions itself | [docs/node-client.md](docs/node-client.md) |

If you're not sure which one you need: pick a **host** guide for any machine
that should run Claude Code sessions other nodes can attach to, and the
**client** guide for a machine that only needs to connect out to those hosts
(for example, a laptop you carry around, or a Windows PC with no WSL
enrollment of its own). Setting up a machine as both? Follow the relevant
host guide, then set `NODE_ROLE=both` in `config/local.env` — no separate
guide is needed.

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
