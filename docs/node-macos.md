# Enroll a macOS host

This guide joins a Mac to the tailnet as a **Tailscale SSH host**: any other node
on the tailnet can then open a shell on it using tailnet identity alone — no
password, no SSH key, no port exposed to the public internet.

**Starting assumption:** this Mac is currently running the Standalone or App
Store Tailscale GUI app. That app has no SSH server — only the open-source
`tailscaled` daemon, installed via the Homebrew `tailscale` formula, serves
Tailscale SSH. This guide switches the Mac from the GUI app to Homebrew
`tailscaled` as part of enrolling it.

## Conventions

- `<node>` and `<user>` are placeholders. Replace `<node>` with this machine's
  Tailscale hostname and `<user>` with the login user you SSH in as — never write
  a real hostname, IP address, tailnet name, or username into a doc, config, or
  commit in this repo.
- Every command below is copy-pasteable as written (after you substitute your own
  `<node>`/`<user>` where they appear).
- Run the commands as a regular user with `sudo` where shown. Do not run this
  guide as `root`.

## 1. Quit and uninstall the Tailscale GUI app

1. Click the Tailscale icon in the menu bar and choose **Quit Tailscale**.
2. Remove the app:

   ```sh
   rm -rf /Applications/Tailscale.app
   ```

3. If Tailscale is listed under System Settings → General → Login Items, remove
   it there too, so it doesn't relaunch on next boot.

This stops the GUI app's own `tailscaled` daemon. It has to be gone before
Homebrew's `tailscaled` can take over as this node's Tailscale backend.

## 2. Install Homebrew Tailscale

```sh
brew install tailscale
```

Verify the installed version before continuing:

```sh
tailscale version
```

It must report `>=1.102.0` — that's the floor `doctor.sh` enforces later. If
Homebrew's cached formula is older than that, run `brew update && brew upgrade
tailscale` and check the version again before moving on.

## 3. Start tailscaled as a background service

```sh
sudo brew services start tailscale
```

`sudo` is required: `brew services` registers `tailscaled` as a `launchd` daemon
running as `root`, which is what lets it survive reboots and keep running
without a logged-in user — the same role the GUI app's daemon used to play, now
owned by Homebrew instead.

## 4. Bring the node up as a Tailscale SSH host

```sh
sudo tailscale up --ssh
```

`tailscale up` prints a login URL the first time you run it on this node. Open
that URL in a browser and sign in with your tailnet identity. Do **not** pass an
auth key on the command line or store one in this repo — the printed URL is the
only credential this guide uses.

`--ssh` advertises this node as a Tailscale SSH host, so other tailnet nodes can
open a shell on it using tailnet identity checks instead of SSH keys or
passwords.

## What you lose by dropping the GUI app

The Standalone/App Store app's menu-bar icon gave you at-a-glance connection
status and a one-click connect/disconnect toggle. Homebrew `tailscaled` has
neither — check status with `tailscale status` and manage the daemon with
`brew services` instead.

If a Mac must keep the GUI app (for example, another user on that machine
relies on the menu-bar toggle), it can still join the tailnet using a
hardened, key-only OpenSSH fallback instead of following this guide — see
[docs/fallback-openssh.md](fallback-openssh.md).

## 5. Install required tools

```sh
brew install tmux git
```

`tmux` is the session multiplexer this node needs to keep Claude Code sessions
alive across disconnects (used starting Epic 2); `doctor.sh` checks for it now
so the node is ready when that lands.

Install the Claude Code CLI (`claude`) per its own official install instructions
for macOS ([docs.claude.com/en/docs/claude-code/setup](https://docs.claude.com/en/docs/claude-code/setup)),
then confirm it's on `PATH`:

```sh
claude --version
```

## 6. Clone the repo and configure this node as a host

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

## 7. Create the workspaces directory

`config/local.env.example` defaults `WORKSPACES_DIR` to `$HOME/workspaces`. If
you kept that default:

```sh
mkdir -p "$HOME/workspaces"
```

If you set a custom `WORKSPACES_DIR` in `config/local.env`, create that path
instead.

## 8. Verify with doctor.sh

```sh
./scripts/doctor.sh
```

Don't re-derive the individual checks by hand (tailscale version, tailnet
membership, SSH advertised, workspaces dir, `~/.ssh` permissions) — `doctor.sh`
is the single source of truth for "is this node ready." Follow whatever fix hint
it prints next to any `FAIL` line, then re-run it.

On macOS, "all-clear" means one thing more than it does on Linux: the exit code
must be `0`, no line may read `FAIL`, **and** the `platform-contract` line must
read `PASS`, not `SKIP`. Unlike native Linux (where `platform-contract` always
`SKIP`s because there's no extra contract to check), macOS has a real check
here — `check_macos_backend` — because it's the only way `doctor.sh` can prove
the GUI app's daemon was actually replaced by Homebrew's. It works by finding
the running `tailscaled` process and checking its path:

- `PASS` — the running `tailscaled` lives under `/opt/homebrew/*` or
  `/usr/local/*` (Homebrew's install prefixes on Apple Silicon and Intel).
- `FAIL` — no `tailscaled` process is found, or the one that's running isn't
  Homebrew's (i.e. the GUI app's daemon is still active). If you see this,
  repeat steps 1–3 to make sure the GUI app is fully quit and removed, then
  re-run `sudo brew services start tailscale`.

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

Either command should open a shell immediately, with no password or key prompt
— the tailnet identity check is what authorizes the connection.

**Check-mode re-authentication:** the default ACL runs in *check mode*, which
periodically re-verifies the connecting user's identity. When the check period
expires, `tailscale ssh` (or the SSH session) will print a browser URL instead
of opening a shell. Open that URL, re-authenticate, then retry the connection —
this is expected behavior, not a failure.

## Security check: macOS Remote Login is not required

Tailscale SSH doesn't use macOS's built-in Remote Login (its `sshd`) at all —
it's served entirely over the tailnet's own encrypted transport by `tailscaled`.
Leave Remote Login (System Settings → General → Sharing → Remote Login) turned
off; this guide's primary path does not need it.

Confirm no `sshd` is listening on this host:

```sh
sudo lsof -iTCP -sTCP:LISTEN | grep -i ssh
```

(`sudo` is required here — without it, `lsof` can miss listening sockets owned
by other users.)

You should see no output. If a line appears, Remote Login (or some other `ssh`
listener) is enabled — turn it off in System Settings → General → Sharing
unless you have a specific reason to keep it, in which case confirm it isn't
reachable from outside the tailnet before treating this host as enrolled.

## Note: bash 3.2 is sufficient

macOS ships `/bin/bash` at version 3.2 (Apple hasn't updated it past the last
GPLv2 release). `doctor.sh` already accounts for this — no script changes are
needed to run it on macOS's stock bash.

## Caveat: tailscaled restart and manual recovery

If `tailscaled` restarts (crash, Homebrew upgrade, reboot before `launchd`
re-enables the service) while you're mid-session, your current Tailscale SSH
connection can drop and won't reconnect until `tailscaled` is back up and the
node re-establishes itself on the tailnet. This is a local recovery step on
**this host only** — it never involves touching or reconfiguring any other
node.

First, check whether `tailscaled` has already recovered on its own:

```sh
brew services list | grep tailscale
tailscale status
```

If it's still down or the node hasn't rejoined the tailnet, check the logs
before falling back to the manual shim below:

```sh
log show --predicate 'process == "tailscaled"' --last 15m
```

(Or open Console.app, select this Mac under Devices, and filter for
`tailscaled`.)

If that doesn't explain it, restart the service:

```sh
sudo brew services restart tailscale
```

If you get locked out of Tailscale SSH after a `tailscaled` restart and need a
manual fallback, use `tailscale serve` to shim a temporary TCP forward to the
local sshd (only if you have a working, locked-down local `sshd` already
running — and note this fallback itself needs a running `tailscaled`; if
`tailscaled` won't come back up, your only recovery is local console/physical
access to the host):

```sh
sudo tailscale serve --tcp 2222 22
```

This exposes local port 22 as port `2222` over the tailnet only (still not on
any public interface). Connect with:

```sh
ssh -p 2222 <user>@<node>
```

Once `tailscaled` and Tailscale SSH are healthy again, remove the shim:

```sh
sudo tailscale serve --tcp 2222 off
```

No step in this guide, including this recovery caveat, touches or reconfigures
any other node on the tailnet.
