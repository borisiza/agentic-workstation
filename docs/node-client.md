# Connect from a client-only node

This guide sets up a machine that only ever *reaches into* the mesh — it opens a
shell on a host over `tailscale ssh`, it never hosts Claude Code sessions of its
own. There is no Tailscale SSH server to advertise, no `$WORKSPACES_DIR`, and none
of the host-only `doctor.sh` checks apply. It covers three platforms: **macOS**,
**native Windows**, and **WSL used purely as a client**. If you instead want this
machine to host Claude Code sessions for other nodes, use
[node-linux.md](node-linux.md), [node-macos.md](node-macos.md), or
[node-wsl.md](node-wsl.md) instead — those enroll the machine as a host, which is
a different (and heavier) setup than this guide.

## Conventions

- `<node>` and `<user>` are placeholders. Replace `<node>` with the *host's*
  Tailscale hostname you're connecting to and `<user>` with the login user you
  SSH in as — never write a real hostname, IP address, tailnet name, or username
  into a doc, config, or commit in this repo. The WSL-as-client section also uses
  `<distro>`, the WSL distro name (e.g. as it appears in `wsl -l -v`) — same rule.
- Every command below is copy-pasteable as written (after you substitute your own
  `<node>`/`<user>`/`<distro>` where they appear).
- Run the commands as a regular user. Do not run this guide as `root`
  (macOS/WSL) or as Administrator (Windows) unless a step says otherwise.

## macOS

Either the Tailscale GUI app or Homebrew's `tailscale` formula works here — unlike
enrolling a Mac as a *host*, a client never has to prove which one is running
(`doctor.sh`'s `platform-contract` check is entirely `SKIP`ped for `client` role,
so there's nothing forcing you off the GUI app).

**1. Install and sign in to Tailscale.**

Pick one:

- GUI app: download from [tailscale.com/download/mac](https://tailscale.com/download/mac)
  (or the App Store), open it, and sign in from the menu-bar icon.
- Homebrew:

  ```sh
  brew install tailscale
  sudo brew services start tailscale
  tailscale up
  ```

  `tailscale up` prints a login URL the first time you run it — open it and sign
  in with your tailnet identity. Don't pass `--ssh`: that flag advertises this
  machine as a Tailscale SSH *host*, which a client-only node doesn't need.

Either way, verify the installed version meets `doctor.sh`'s `>=1.102.0` floor
(this check applies to every role, not just hosts):

```sh
tailscale version
```

**2. Install the remaining tools `doctor.sh` checks for.**

```sh
brew install tmux git
```

Install the Claude Code CLI (`claude`) per its own official install instructions
for macOS ([docs.claude.com/en/docs/claude-code/setup](https://docs.claude.com/en/docs/claude-code/setup)),
then confirm it's on `PATH`:

```sh
claude --version
```

(`doctor.sh` runs the same common-tool checks — `tmux`, `claude`, `git` — for
every role, not just hosts, so they're needed here too even though this node
never runs a session of its own.)

**3. Make sure `~/.ssh` has the right permissions.**

```sh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

You don't need an SSH key pair for this guide — Tailscale SSH authorizes by
tailnet identity, not by key. `doctor.sh`'s `ssh-key-perms` check `SKIP`s cleanly
when no `id_*` key is present.

**4. Clone the repo and configure this node as a client.**

If `$HOME/agentic-workstation` already exists from a previous attempt, `cd` into
it and `git pull` instead of cloning again.

```sh
git clone <repo-url> "$HOME/agentic-workstation"
cd "$HOME/agentic-workstation"
cp config/local.env.example config/local.env
```

Edit `config/local.env` and set:

```
NODE_ROLE=client
```

`config/local.env` is gitignored — it never gets committed.

**5. Verify with `doctor.sh`.**

```sh
./scripts/doctor.sh
```

For `NODE_ROLE=client`, `run_host_checks`'s `client` branch
(`scripts/doctor.sh:313`-`317`) emits `SKIP` for all three host-only checks —
`tailscale-ssh-advertised`, `workspaces-dir`, `platform-contract` — unconditionally,
without even inspecting the platform. Every common check (`tailscale-installed`,
`tailnet-membership`, `tmux-installed`, `claude-installed`, `git-installed`,
`ssh-dir-perms`, `ssh-key-perms`) should read `PASS` (or `SKIP` for
`ssh-key-perms` if you have no keys). This step is done when the exit code is `0`
and no line reads `FAIL`.

**6. Reach a host.**

From this Mac, connect to a machine already enrolled as a host
([node-linux.md](node-linux.md), [node-macos.md](node-macos.md), or
[node-wsl.md](node-wsl.md)):

```sh
tailscale ssh <user>@<node>
```

or, if Tailscale SSH isn't available, plain SSH over the tailnet still works:

```sh
ssh <user>@<node>
```

Either command should open a shell immediately, with no password or key prompt.

**Check-mode re-authentication:** the tailnet's default ACL runs in *check mode*,
which periodically re-verifies the connecting user's identity. When the check
period expires, `tailscale ssh` (or the SSH session) prints a browser URL instead
of opening a shell. Open that URL, re-authenticate, then retry the connection —
this is expected behavior, not a failure.

## Native Windows

The Windows Tailscale app and the bash shell you use to run `doctor.sh` are two
independent things — don't conflate them. Tailscale itself installs and signs in
as a native Windows app; it establishes this PC's tailnet identity and works from
PowerShell/cmd with no bash required. `doctor.sh`, on the other hand, is a bash
script, so it needs *some* bash shell to execute — either Git Bash or WSL — purely
to run that one check. That shell doesn't need its own separate Tailscale
identity; it only needs to *see* the identity the Windows app already
established.

**1. Install and sign in to Tailscale (native, no bash needed).**

Download from [tailscale.com/download/windows](https://tailscale.com/download/windows)
(or `winget install tailscale.tailscale` in PowerShell), then sign in from the
tray icon. Don't advertise SSH (`--ssh`) — that's for hosts, not clients.

Confirm it's up from PowerShell, and verify the installed version meets
`doctor.sh`'s `>=1.102.0` floor (this check applies to every role, not just
hosts):

```
PS> tailscale status
PS> tailscale version
```

**2. Pick a bash shell to run `doctor.sh` in: Git Bash or WSL.**

- **Git Bash** (from [Git for Windows](https://git-scm.com/download/win)) already
  gives you `git`, and its mingw-based bash resolves bare commands like
  `tailscale` and `claude` against `tailscale.exe`/`claude.exe` on the Windows
  `PATH` automatically, so `doctor.sh`'s `tailscale-installed` and
  `claude-installed` checks can see them with no extra setup. There is no
  first-party Windows build of `tmux`, though — if your Git Bash environment
  doesn't already have `tmux` reachable via `command -v tmux`, use WSL instead
  for this step; don't spend time hunting for a Windows tmux port just to
  satisfy one check.
- **WSL**, used *here* only as a shell to run `doctor.sh` — not as its own
  tailnet node (that's a different setup; see the WSL-as-a-client section
  below, or [node-wsl.md](node-wsl.md) to enroll it as a host instead). Open a
  distro (`PS> wsl -d <distro>`) and:

  ```sh
  sudo apt-get install -y tmux git      # Debian/Ubuntu
  sudo yum install -y tmux git          # RHEL/Fedora/CentOS
  ```

  Install the Claude Code CLI (`claude`) per its own official Linux install
  instructions ([docs.claude.com/en/docs/claude-code/setup](https://docs.claude.com/en/docs/claude-code/setup)),
  then confirm `claude --version` works.

  Rather than installing a second copy of Tailscale inside the distro (which
  would give it its own separate tailnet identity — a host-enrollment step this
  guide deliberately doesn't cover), point `doctor.sh` at the same
  Windows-managed Tailscale from step 1 by symlinking the Windows binary onto
  the distro's `PATH` (WSL2 can invoke Windows `.exe` files transparently):

  ```sh
  sudo ln -sf "/mnt/c/Program Files/Tailscale/tailscale.exe" /usr/local/bin/tailscale
  ```

  (Adjust the path if you installed Tailscale somewhere other than the default
  location.) `tailscale status`/`tailscale version` run inside the distro now
  report the same Windows-side identity from step 1.

**3. Make sure `~/.ssh` has the right permissions**, in whichever shell you
picked for step 2:

```sh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

**4. Clone the repo and configure this node as a client**, again in that same
shell:

```sh
git clone <repo-url> "$HOME/agentic-workstation"
cd "$HOME/agentic-workstation"
cp config/local.env.example config/local.env
```

Edit `config/local.env` and set:

```
NODE_ROLE=client
```

**5. Verify with `doctor.sh`**, from the same shell:

```sh
./scripts/doctor.sh
```

Host-only checks (`tailscale-ssh-advertised`, `workspaces-dir`,
`platform-contract`) read `SKIP` for `NODE_ROLE=client`
(`scripts/doctor.sh:313`-`317`) — this holds regardless of which shell or
platform you're running it from, since the `client` branch never inspects the
platform at all. Common checks should read `PASS`.

**6. Reach a host.**

This step doesn't need the bash shell at all — Windows' native OpenSSH client and
the Tailscale CLI both work directly from PowerShell:

```
PS> tailscale ssh <user>@<node>
```

or, using Windows' built-in OpenSSH client (present by default on current
Windows 10/11; add it via Settings → Optional Features → OpenSSH Client if
missing):

```
PS> ssh <user>@<node>
```

Either command should open a shell immediately, with no password or key prompt.

**Check-mode re-authentication:** the tailnet's default ACL runs in *check mode*,
which periodically re-verifies the connecting user's identity. When the check
period expires, `tailscale ssh` (or the SSH session) prints a browser URL instead
of opening a shell. Open that URL, re-authenticate, then retry the connection —
this is expected behavior, not a failure.

## WSL (as a client)

This section makes a WSL distro itself join the tailnet as a client — different
from the previous section, where WSL was only a bash shell borrowing Windows'
Tailscale identity. Pick this section if you want the distro to have its own
tailnet identity and reach hosts directly from inside it.

Client role never triggers `platform-contract`, so unlike
[node-wsl.md](node-wsl.md) (which enrolls a WSL distro as a *host*), this guide
needs none of the `systemd`/`[boot]` maneuvering that guide requires — the
distro's default `init` is fine.

**1. Pick a distro and open it.**

```
PS> wsl -l -v
PS> wsl -d <distro>
```

**2. Install Tailscale inside the distro.**

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
`ubuntu/noble`) — a different placeholder than `<distro>` (your WSL distro's
name); don't confuse the two. If you picked a non-Ubuntu distro, follow its own
package manager's Tailscale install instead, per the RHEL/Fedora/CentOS path in
[node-linux.md](node-linux.md).

Verify the installed version meets `doctor.sh`'s `>=1.102.0` floor:

```sh
tailscale version
```

**3. Start `tailscaled` and sign in.**

This distro has no `systemd`, and the `tailscale` apt package only ships a
`systemd` unit (no legacy init script), so `systemctl`/`service` won't start it
here. Run `tailscaled` directly as a background process instead — the same
pattern used to run it in any other non-`systemd` environment (e.g. a
container):

```sh
sudo mkdir -p /var/lib/tailscale
pgrep -x tailscaled >/dev/null || \
  sudo tailscaled --state=/var/lib/tailscale/tailscaled.state >/dev/null 2>&1 &
for i in 1 2 3 4 5; do sudo tailscale status >/dev/null 2>&1 && break; sleep 1; done
sudo tailscale up
```

`pgrep` skips starting a second `tailscaled` if one is already running (e.g.
you're repeating this step after a disconnect). The `for` loop gives the
daemon a moment to open its control socket before `tailscale up` talks to it —
on a freshly started distro, calling `tailscale up` immediately after
backgrounding `tailscaled` can otherwise race a socket that isn't ready yet.

This `tailscaled` process lives only as long as this WSL session — a client
doesn't need it to survive an unattended restart the way a host does (that's a
host-only concern; see [node-wsl.md](node-wsl.md) if you want this distro to
run `tailscaled` under `systemd` instead so it does survive restarts). If the
distro restarts or `tailscaled` stops, repeat this step before reconnecting.

`tailscale up` prints a login URL the first time you run it — open it and sign
in with your tailnet identity. Don't pass `--ssh`: that advertises this distro
as a Tailscale SSH host, which a client doesn't need.

**4. Install the remaining tools `doctor.sh` checks for.**

```sh
sudo apt-get install -y tmux git      # Debian/Ubuntu
sudo yum install -y tmux git          # RHEL/Fedora/CentOS
```

Install the Claude Code CLI (`claude`) per its own official Linux install
instructions ([docs.claude.com/en/docs/claude-code/setup](https://docs.claude.com/en/docs/claude-code/setup)),
then confirm it's on `PATH`:

```sh
claude --version
```

**5. Make sure `~/.ssh` has the right permissions.**

```sh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

**6. Clone the repo and configure this node as a client.**

If `$HOME/agentic-workstation` already exists from a previous attempt, `cd` into
it and `git pull` instead of cloning again.

```sh
git clone <repo-url> "$HOME/agentic-workstation"
cd "$HOME/agentic-workstation"
cp config/local.env.example config/local.env
```

Edit `config/local.env` and set:

```
NODE_ROLE=client
```

**7. Verify with `doctor.sh`.**

```sh
./scripts/doctor.sh
```

For `NODE_ROLE=client`, `run_host_checks`'s `client` branch
(`scripts/doctor.sh:313`-`317`) emits `SKIP` for `tailscale-ssh-advertised`,
`workspaces-dir`, and `platform-contract` directly — it never even calls
`is_wsl()` or checks for `systemd` as PID 1, so none of step 2-3's precedent
from `node-wsl.md` about `systemd` applies here. Common checks should read
`PASS`.

**8. Reach a host.**

```sh
tailscale ssh <user>@<node>
```

or, if Tailscale SSH isn't available, plain SSH over the tailnet still works:

```sh
ssh <user>@<node>
```

Either command should open a shell immediately, with no password or key prompt.

**Check-mode re-authentication:** the tailnet's default ACL runs in *check mode*,
which periodically re-verifies the connecting user's identity. When the check
period expires, `tailscale ssh` (or the SSH session) prints a browser URL instead
of opening a shell. Open that URL, re-authenticate, then retry the connection —
this is expected behavior, not a failure.

## Verification

**Time estimate, not a timed live run:** no second machine was available to
run an actual stopwatch test of this guide, so this is a step count against
the guide's own numbered steps rather than a measurement. Each platform's path
is 6-8 short steps (install + sign in, install common tools, `~/.ssh`
permissions, clone + configure, `doctor.sh`, connect to a host); every step is
a handful of copy-pasteable commands or, for the GUI parts (sign-in, app
install), a couple of clicks. The same reasoning underlies the `doctor.sh`
all-clear standing in for checks that can't be run live in
[node-wsl.md](node-wsl.md#unattended-reachability-outside-this-repo) and
[node-macos.md](node-macos.md#8-verify-with-doctorsh): a first-time reader
following any one of the three paths above end to end should land comfortably
under 30 minutes, and touches no file or state on any other node, since every
step here is local to the client machine plus reading (never writing) the
tailnet via `tailscale up`/`tailscale ssh`.
