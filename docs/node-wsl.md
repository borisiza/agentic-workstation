# Enroll a Windows host via WSL2

This guide joins a Windows machine to the tailnet as a **Tailscale SSH host** by
making a WSL2 Linux distro act as its own tailnet node. Windows has no native path
to this: the Windows Tailscale app has no SSH server, so the distro itself — not
Windows — becomes the Tailscale SSH host. Any other node on the tailnet can then
open a shell on the distro using tailnet identity alone — no password, no SSH key,
no port exposed to the public internet.

## Conventions

- `<distro>` is the WSL distro name (e.g. as it appears in `wsl -l -v`), `<node>` is
  this distro's Tailscale hostname, `<user>` is the login user you SSH in as,
  `<distro-codename>` is the Tailscale apt-repo path segment used in step 4, and
  `<repo-url>` is this repo's git clone URL used in step 7 — all placeholders.
  Never write a real distro name, hostname, IP address, tailnet name, username,
  codename, or repo URL into a doc, config, or commit in this repo.
- Commands prefixed `PS>` run in Windows PowerShell (outside the distro). Commands
  with no prefix run as a regular user inside the WSL2 distro, with `sudo` where
  shown. Do not run the in-distro steps as `root`.
- Every command below is copy-pasteable as written (after you substitute your own
  `<distro>`/`<node>`/`<user>`/`<distro-codename>`/`<repo-url>` where they appear).

## 1. Check the WSL version and pick a distro

```
PS> wsl --version
```

You need `wsl.exe` version `>= 2.4.4`. If it's older, update it with
`wsl --update`. This floor matters later: the
[Unattended reachability](#unattended-reachability-outside-this-repo) section
below depends on `instanceIdleTimeout`, a `.wslconfig` setting whose availability
depends on your WSL version (see the assumption flagged in that section).

List your installed distros and pick **one** to enroll as the host:

```
PS> wsl -l -v
```

This guide enrolls **one** distro as the host. If you have multiple WSL
distros, each could in principle be enrolled as its own separate tailnet node,
but the steps below cover enrolling one distro at a time — repeat the whole
guide per distro if you want more than one enrolled.

WSL2's default distro is Ubuntu, so this guide's package-manager commands use
`apt`. If you picked a different distro, follow its own package manager instead
— see [docs/node-linux.md](node-linux.md) for the RHEL/Fedora/CentOS (`yum`/`dnf`)
equivalents of every `apt` command below.

## 2. Enable systemd in the distro

Open a shell in the distro you picked (`PS> wsl -d <distro>`), then check
whether `/etc/wsl.conf` already has a `[boot]` section:

```sh
grep -q '^\[boot\]' /etc/wsl.conf 2>/dev/null && echo "has [boot]" || echo "no [boot]"
```

If it prints `has [boot]`, open `/etc/wsl.conf` in an editor and add
`systemd=true` under the existing `[boot]` section by hand — do not append a
second `[boot]` block. Only if it prints `no [boot]`, append the full block:

```sh
sudo tee -a /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
```

## 3. Restart the distro and confirm systemd is PID 1

From Windows (not inside the distro), shut down all WSL2 instances so the
`systemd=true` setting takes effect on next launch:

```
PS> wsl --shutdown
```

**Warning:** `wsl --shutdown` stops **all** running WSL2 distros on the
machine, not just the one you're configuring — save any work in other running
distros before running this command.

Then reopen the distro (`PS> wsl -d <distro>`) and confirm `systemd` is now PID 1:

```sh
ps -p 1 -o comm=
```

This should print `systemd`. This is exactly what `doctor.sh`'s
`check_wsl_pid1` (`scripts/doctor.sh:276`) checks later — if this prints anything
else, `/etc/wsl.conf` wasn't saved correctly or the distro wasn't fully restarted
with `wsl --shutdown`; fix that before continuing.

## 4. Install Tailscale inside the distro

**Debian/Ubuntu (apt) — WSL2's default distro:**

```sh
curl -fsSL https://pkgs.tailscale.com/stable/<distro-codename>/tailscale-archive-keyring.gpg \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/<distro-codename>/tailscale.list \
  | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt-get update
sudo apt-get install -y tailscale
```

Replace `<distro-codename>` with the codename path segment from
[tailscale.com/download/linux](https://tailscale.com/download/linux) (e.g.
`ubuntu/noble`) — note this is a different placeholder than `<distro>` (your WSL
distro's name); don't confuse the two.

If you picked a non-Ubuntu distro in step 1, follow its package manager's
Tailscale install instead, per the RHEL/Fedora/CentOS path in
[docs/node-linux.md](node-linux.md).

Verify the installed version before continuing — `doctor.sh`'s
`check_tailscale_installed` (`scripts/doctor.sh:134`) requires `>= 1.102.0`, so
confirm the version printed below meets that floor, not just that a version
prints:

```sh
tailscale version
```

Enable `tailscaled` as a systemd service so it survives distro restarts (this is
only possible because step 3 made systemd PID 1):

```sh
sudo systemctl enable --now tailscaled
```

## 5. Bring the distro up as a Tailscale SSH host

```sh
sudo tailscale up --ssh
```

`tailscale up` prints a login URL the first time you run it on this node. Open
that URL in a browser and sign in with your tailnet identity. Do **not** pass an
auth key on the command line or store one in this repo — the printed URL is the
only credential this guide uses.

`--ssh` advertises this distro as a Tailscale SSH host, so other tailnet nodes
can open a shell on it using tailnet identity checks instead of SSH keys or
passwords. Once this completes, the distro shows up on the tailnet as its own
node with its own MagicDNS name — separate from Windows, which never needs to
join the tailnet itself for this guide's purposes (see "Windows-side Tailscale
app is optional" below).

## 6. Install required tools

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

## 7. Clone the repo and configure this node as a host

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

## 8. Create the workspaces directory

`config/local.env.example` defaults `WORKSPACES_DIR` to `$HOME/workspaces`. If
you kept that default:

```sh
mkdir -p "$HOME/workspaces"
```

If you set a custom `WORKSPACES_DIR` in `config/local.env`, create that path
instead.

## 9. Verify with doctor.sh

```sh
./scripts/doctor.sh
```

Don't re-derive the individual checks by hand (tailscale version, tailnet
membership, SSH advertised, workspaces dir, `~/.ssh` permissions) — `doctor.sh`
is the single source of truth for "is this node ready." Follow whatever fix hint
it prints next to any `FAIL` line, then re-run it.

On WSL, "all-clear" means one thing more than it does on native Linux: the exit
code must be `0`, no line may read `FAIL`, **and** the `platform-contract` line
must read `PASS`, not `SKIP`. `platform-contract` diverges three ways depending
on the host: native Linux always `SKIP`s it (no extra contract to check), macOS
requires `PASS` via a Homebrew-daemon-path check, and WSL requires `PASS` via
`check_wsl_pid1` (`scripts/doctor.sh:276`), dispatched from
`check_platform_contract` (`scripts/doctor.sh:286`) whenever `is_wsl()`
(`scripts/doctor.sh:248`) is true on Linux. It works by checking that `systemd`
is PID 1:

- `PASS` — `ps -p 1 -o comm=` reports `systemd`.
- `FAIL` — anything else. This means `/etc/wsl.conf` wasn't set to
  `[boot] systemd=true`, or the distro wasn't restarted with `wsl --shutdown`
  after editing it. Repeat steps 2–3.

## Unattended reachability (outside this repo)

None of this repo's scripts touch or can verify the following — they're Windows
OS-level settings, not part of `doctor.sh` or any other script here. Set these up
so the distro stays reachable over Tailscale SSH after a Windows restart, with
nobody touching the desktop:

**1. Prevent WSL2 from idling the distro out.** WSL2 distros suspend by default
after a period of inactivity, which would take the distro's `tailscaled` (and
thus its tailnet reachability) down with it. Open (or create)
`%UserProfile%\.wslconfig` on Windows and check whether it already has a
`[wsl2]` section. If it does, add `vmIdleTimeout=-1` and
`instanceIdleTimeout=-1` under that existing section by hand — do not create a
second `[wsl2]` section. Only if the file has no `[wsl2]` section yet, add:

```
[wsl2]
vmIdleTimeout=-1
instanceIdleTimeout=-1
```

`vmIdleTimeout=-1` disables the idle timeout for the WSL2 VM as a whole;
`instanceIdleTimeout=-1` disables it for the individual distro instance.

> **Assumption to verify on the host:** `instanceIdleTimeout` requires a WSL
> version at or above the `wsl --version` floor checked in step 1
> (`>= 2.4.4`) — older `wsl.exe` builds may not recognize this key. Confirm your
> installed version supports it; if `wsl --update` doesn't get you there, the
> distro may still idle-suspend despite this setting.

**2. Keep the distro running across logons.** `.wslconfig` alone won't launch the
distro — something still needs to start it. Add a Windows Task Scheduler entry
that runs at logon and keeps the distro alive:

- Trigger: **At log on** (any user, or the specific account this host runs as).
- Action: start a program —
  ```
  C:\Windows\System32\wsl.exe -d <distro> --exec sleep infinity
  ```
  Use the fully-qualified path, not a bare `wsl.exe` — under "run whether
  logged on or not," the task runs in a context whose `PATH` may not include
  `wsl.exe`, so a bare reference can fail to resolve.
- Run whether the user is logged on or not, and run with highest privileges, so
  it survives an unattended restart-and-autologon cycle.

**3. Disable Windows sleep/no-activity power settings.** If Windows itself goes
to sleep, WSL2 (and the distro inside it) goes down with it, regardless of the
`.wslconfig` settings above. In Settings → System → Power & battery (or the
legacy Control Panel → Power Options), set **Sleep** and **Screen off after
inactivity** to **Never** for the plan this host uses, both on battery and
plugged in (if a laptop) or the single AC plan (if a desktop).

With all three in place: after a Windows restart and logon, no one needs to
touch the desktop — the Task Scheduler entry starts the distro, `.wslconfig`
keeps it from idling back out, and `tailscaled` (already enabled under systemd
in step 4) comes up and rejoins the tailnet on its own. Within a few minutes,
another node should be able to run `tailscale ssh <user>@<node>` into the distro.
The only automatable proof of this, from inside this repo, is `doctor.sh`'s
all-clear (step 9) run again after the restart — there is no script here that
can verify the Windows-side restart-and-autologon path itself.

## Windows-side Tailscale app is optional

The Windows Tailscale app (if installed) plays **client role only** — it lets
Windows itself reach other tailnet nodes, but it is not required for the distro
to act as its own tailnet host, and this guide does not install or configure it.
The distro joined the tailnet on its own in step 5, with its own identity and
MagicDNS name, independent of whatever Windows does or doesn't have installed.

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

Inside the distro, confirm that no `sshd` is listening on any interface other
than the tailnet, and that password/root login aren't reachable on the primary
path:

```sh
sudo ss -tlnp | grep :22
```

(`sudo` is required here — without it, `ss` cannot report which process owns a
listening socket, so the check can miss a stray `sshd`.)

- You should see no `sshd` (or any process) bound to `0.0.0.0:22`, a LAN IP, or
  any public interface — Tailscale SSH doesn't need a listening `sshd` on port
  22 at all; it's served over the tailnet's own encrypted transport. This
  matters more on WSL2 than on bare-metal Linux: WSL2's NAT networking can
  expose a distro's ports to the Windows host's LAN in some configurations, so
  confirm nothing is listening beyond the tailnet.
- If a system `sshd` happens to be running for other reasons, confirm its
  effective config (not just the main file, in case a drop-in under
  `/etc/ssh/sshd_config.d/` overrides it) has password and root login disabled:

  ```sh
  sudo sshd -T | grep -Ei 'passwordauthentication|permitrootlogin'
  ```

  Both should read `no` — password and root login must not be reachable on the
  primary (Tailscale SSH) path.

If `ss -tlnp` shows an `sshd` bound to a non-tailnet address, stop and lock it
down (or disable it) before treating this host as enrolled.

## Caveat: tailscaled restart and manual recovery

If `tailscaled` restarts (crash, package upgrade, distro reboot before the
service is re-enabled) while you're mid-session, your current Tailscale SSH
connection can drop and won't reconnect until `tailscaled` is back up and the
node re-establishes itself on the tailnet. This is a local recovery step on
**this distro only** — it never involves touching or reconfiguring Windows, any
other distro, or any other node.

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
access to the Windows host, e.g. `wsl -d <distro>` from an interactive Windows
session):

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
