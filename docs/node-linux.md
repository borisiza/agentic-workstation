# Enroll a Linux host

This guide joins a fresh Linux machine to the tailnet as a **Tailscale SSH host**: any
other node on the tailnet can then open a shell on it using tailnet identity alone —
no password, no SSH key, no port exposed to the public internet.

## Conventions

- `<node>` and `<user>` are placeholders. Replace `<node>` with this machine's
  Tailscale hostname and `<user>` with the login user you SSH in as — never write a
  real hostname, IP address, tailnet name, or username into a doc, config, or commit
  in this repo.
- Every command below is copy-pasteable as written (after you substitute your own
  `<node>`/`<user>` where they appear).
- Run the commands as a regular user with `sudo` where shown. Do not run this guide
  as `root`.

## 1. Install Tailscale 1.102.3

Install from Tailscale's official package repository for your distribution, then
pin the install to version `1.102.3`.

**Debian/Ubuntu (apt):**

```sh
curl -fsSL https://pkgs.tailscale.com/stable/<distro>/tailscale-archive-keyring.gpg \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/<distro>/tailscale.list \
  | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt-get update

# Confirm the exact package string for 1.102.3 before installing -- the apt
# revision suffix varies by distro/arch, so don't guess it.
apt-cache madison tailscale | grep 1.102.3
sudo apt-get install -y tailscale=<version-string-from-apt-cache-madison-above>
```

Replace `<distro>` with your distro/codename path segment from
[tailscale.com/download/linux](https://tailscale.com/download/linux) (e.g.
`ubuntu/noble`, `debian/bookworm`). If more than one line matches, pick the one for
your architecture (`dpkg --print-architecture`).

**RHEL/Fedora/CentOS (yum/dnf):**

```sh
# yum-config-manager needs yum-utils/dnf-plugins-core; install it first if missing
command -v yum-config-manager >/dev/null || sudo dnf install -y dnf-plugins-core

sudo yum-config-manager --add-repo https://pkgs.tailscale.com/stable/<distro>/tailscale.repo
sudo yum list --showduplicates tailscale | grep 1.102.3
sudo yum install -y tailscale-<version-string-from-yum-list-above>
```

If more than one line matches, pick the one for your architecture (`uname -m`).

Replace `<distro>` with your distro/version path segment (e.g. `rhel/9`,
`fedora/40`).

Verify the installed version before continuing:

```sh
tailscale version
```

## 2. Bring the node up as a Tailscale SSH host

```sh
sudo tailscale up --ssh
```

`tailscale up` prints a login URL the first time you run it on this node. Open that
URL in a browser and sign in with your tailnet identity. Do **not** pass an auth
key on the command line or store one in this repo — the printed URL is the only
credential this guide uses.

`--ssh` advertises this node as a Tailscale SSH host, so other tailnet nodes can
open a shell on it using tailnet identity checks instead of SSH keys or passwords.

## 3. Install required tools

```sh
sudo apt-get install -y tmux git      # Debian/Ubuntu
sudo yum install -y tmux git          # RHEL/Fedora/CentOS
```

`tmux` is the session multiplexer this node needs to keep Claude Code sessions
alive across disconnects (used starting Epic 2); `doctor.sh` checks for it now so
the node is ready when that lands.

Install the Claude Code CLI (`claude`) per its own official install instructions
for Linux ([docs.claude.com/en/docs/claude-code/setup](https://docs.claude.com/en/docs/claude-code/setup)),
then confirm it's on `PATH`:

```sh
claude --version
```

## 4. Clone the repo and configure this node as a host

If `$HOME/agentic-workstation` already exists from a previous attempt, `cd` into
it and `git pull` instead of cloning again.

```sh
git clone <repo-url> "$HOME/agentic-workstation"
cd "$HOME/agentic-workstation"
cp config/local.env.example config/local.env
```

Edit `config/local.env` and set:

```
NODE_ROLE=host
```

`config/local.env` is gitignored — it never gets committed, so it's safe to put
this node's real role and any host-local settings there.

## 5. Create the workspaces directory

`config/local.env.example` defaults `WORKSPACES_DIR` to `$HOME/workspaces`. If you
kept that default:

```sh
mkdir -p "$HOME/workspaces"
```

If you set a custom `WORKSPACES_DIR` in `config/local.env`, create that path
instead.

## 6. Verify with doctor.sh

```sh
./scripts/doctor.sh
```

Don't re-derive the individual checks by hand (tailscale version, tailnet
membership, SSH advertised, workspaces dir, `~/.ssh` permissions) — `doctor.sh` is
the single source of truth for "is this node ready." Follow whatever fix hint it
prints next to any `FAIL` line, then re-run it. This step is done when the exit
code is `0` and no line reads `FAIL`. A `SKIP` line is expected and fine —
`platform-contract` always shows `SKIP` on native (non-WSL) Linux since there is
no extra platform check for it (only macOS and WSL hosts have one); client-only
nodes additionally SKIP `tailscale-ssh-advertised` and `workspaces-dir`.

## Tailnet ACL: no policy file needed

This guide relies on the tailnet's **default ACL** (`autogroup:member ->
autogroup:self`, in check mode): tailnet members can already reach their own
devices, including this new host, with no custom policy required. Do not commit
an ACL policy file for this story — the default is sufficient.

## Verify from another tailnet node

From a different node already on the same tailnet:

```sh
tailscale ssh <user>@<node>
```

or, if Tailscale SSH isn't available on the client, plain SSH over the tailnet
still works:

```sh
ssh <user>@<node>
```

Either command should open a shell immediately, with no password or key prompt —
the tailnet identity check is what authorizes the connection.

**Check-mode re-authentication:** the default ACL runs in *check mode*, which
periodically re-verifies the connecting user's identity. When the check period
expires, `tailscale ssh` (or the SSH session) will print a browser URL instead of
opening a shell. Open that URL, re-authenticate, then retry the connection — this
is expected behavior, not a failure.

## Security check: confirm no non-tailnet sshd exposure

On the enrolled host, confirm that no `sshd` is listening on any interface other
than the tailnet, and that password/root login aren't reachable on the primary
path:

```sh
sudo ss -tlnp | grep :22
```

(`sudo` is required here — without it, `ss` cannot report which process owns a
listening socket, so the check can miss a stray `sshd`.)

- You should see no `sshd` (or any process) bound to `0.0.0.0:22`, a LAN IP, or any
  public interface — Tailscale SSH doesn't need a listening `sshd` on port 22 at
  all; it's served over the tailnet's own encrypted transport.
- If a system `sshd` happens to be running for other reasons, confirm its
  effective config (not just the main file, in case a drop-in under
  `/etc/ssh/sshd_config.d/` overrides it) has password and root login disabled:

  ```sh
  sudo sshd -T | grep -Ei 'passwordauthentication|permitrootlogin'
  ```

  Both should read `no` — password and root login must not be reachable on the
  primary (Tailscale SSH) path.

If `ss -tlnp` shows an `sshd` bound to a non-tailnet address, stop and lock it down
(or disable it) before treating this host as enrolled.

## Caveat: tailscaled restart and manual recovery

If `tailscaled` restarts (crash, package upgrade, reboot before the service is
re-enabled) while you're mid-session, your current Tailscale SSH connection can
drop and won't reconnect until `tailscaled` is back up and the node re-establishes
itself on the tailnet. This is a local recovery step on **this host only** — it
never involves touching or reconfiguring any other node.

First, check whether `tailscaled` has already recovered on its own:

```sh
systemctl status tailscaled
tailscale status
```

If it's still down or the node hasn't rejoined the tailnet, check the logs
(`journalctl -u tailscaled`) before falling back to the manual shim below.

If you get locked out of Tailscale SSH after a `tailscaled` restart and need a
manual fallback, use `tailscale serve` to shim a temporary TCP forward to the
local sshd (only if you have a working, locked-down local `sshd` per the check
above — and note this fallback itself needs a running `tailscaled`; if
`tailscaled` won't come back up, your only recovery is local console/physical
access to the host):

```sh
sudo tailscale serve --tcp 2222 22
```

This exposes local port 22 as port `2222` over the tailnet only (still not on any
public interface). Connect with:

```sh
ssh -p 2222 <user>@<node>
```

Once `tailscaled` and Tailscale SSH are healthy again, remove the shim:

```sh
sudo tailscale serve --tcp 2222 off
```
