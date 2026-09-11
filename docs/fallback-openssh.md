# Fallback: hardened key-only OpenSSH over the tailnet

**This is a documented exception, not the primary path.** Every host should
try [docs/node-linux.md](node-linux.md), [docs/node-macos.md](node-macos.md),
or [docs/node-wsl.md](node-wsl.md) first and enroll as a **Tailscale SSH**
host. Use this guide only for a host that genuinely cannot serve Tailscale
SSH — for example, a Mac that must keep the Tailscale GUI app running for
another user's menu-bar toggle, so it can't run Homebrew `tailscaled` (the
only backend that serves Tailscale SSH).

This guide configures that host's operating-system `sshd` as a **strictly
opt-in, key-only, hardened fallback**, reachable only over the tailnet. It
does not touch, weaken, or replace the Tailscale-SSH-primary path on any
other node.

## Conventions

- `<user>` is a placeholder: the login account this fallback allows in. Never
  write a real hostname, IP address, tailnet name, username, or key material
  into a doc, config, or commit in this repo.
- Every command below is copy-pasteable as written (after you substitute your
  own `<user>`).
- Run the commands as a regular user with `sudo` where shown. Do not run this
  guide as `root`.

## Why this is opt-in, not automatic

`doctor.sh` never auto-detects whether a host needs this fallback. The single
toggle is `FALLBACK_SSHD` in `config/local.env` (default `0`). You decide a
host needs the fallback, follow this guide by hand, then set
`FALLBACK_SSHD=1` yourself. There is no `scripts/enroll.sh` or client-key
enrollment automation for this path (that is a separate, later story) — you
manage the host's `sshd_config` and `~/.ssh/authorized_keys` directly.

## 1. Install/enable an OpenSSH server

**macOS:** enable Remote Login.

1. System Settings → General → Sharing → turn on **Remote Login**.
2. Restrict it to the account you'll connect as, not "All users", if the
   toggle offers that choice.

Or from the command line:

```sh
sudo systemsetup -setremotelogin on
```

**Linux/WSL (Debian/Ubuntu):**

```sh
sudo apt-get install -y openssh-server
sudo systemctl enable --now ssh
```

**Linux (RHEL/Fedora/CentOS):**

```sh
sudo dnf install -y openssh-server
sudo systemctl enable --now sshd
```

## 2. Configure the four hardening settings

Edit the host's effective `sshd_config` (usually `/etc/ssh/sshd_config`, but
check `/etc/ssh/sshd_config.d/*.conf` too — a drop-in there can silently
override the main file). Set:

```
PasswordAuthentication no
PermitRootLogin no
KbdInteractiveAuthentication no
AllowUsers <user>
```

Replace `<user>` with the single login account this fallback should accept —
never `root`, and never leave `AllowUsers` unset (an unset `AllowUsers`
allows every local account, which defeats the point of restricting this
fallback to one identity).

Restart sshd so the new config takes effect:

```sh
# Linux (Debian/Ubuntu)
sudo systemctl restart ssh

# Linux (RHEL/Fedora/CentOS)
sudo systemctl restart sshd

# macOS: toggle Remote Login off then on again in System Settings, or:
sudo launchctl kickstart -k system/com.openssh.sshd
```

## 3. Verify the hardening with `sshd -T`

`sshd -T` prints sshd's fully resolved, effective configuration — including
any drop-in overrides — so it's the only reliable way to confirm what's
actually active (reading `sshd_config` by eye can miss a drop-in that
overrides it):

```sh
sudo sshd -T | grep -Ei 'passwordauthentication|permitrootlogin|kbdinteractiveauthentication|allowusers'
```

You should see exactly:

```
passwordauthentication no
permitrootlogin no
kbdinteractiveauthentication no
allowusers <user>
```

If any line differs, fix it in `sshd_config` (or its drop-in), restart sshd,
and re-check before moving on. `doctor.sh`'s `sshd-hardening` check (below)
automates exactly this verification.

## 4. Set `~/.ssh` permissions and install the allowed key

On the host, as `<user>`:

```sh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

Append the **public** key of whichever client should be allowed in to
`~/.ssh/authorized_keys` (never copy a private key anywhere). The key comes
from the client machine's own `~/.ssh/id_ed25519.pub` (or equivalent
`.pub` file) — copy that one line over, for example:

```sh
echo "ssh-ed25519 AAAA...client-key-here" >> ~/.ssh/authorized_keys
```

Then lock down its permissions:

```sh
chmod 600 ~/.ssh/authorized_keys
```

OpenSSH refuses to honor `authorized_keys` (or even the whole `~/.ssh`
directory) if the permissions are too open — `sshd` will silently fall back
to rejecting the key rather than explaining why, so get this right before
testing a connection.

## 5. Set `FALLBACK_SSHD=1` and join the tailnet normally

In `config/local.env` (copy from `config/local.env.example` if you haven't
already):

```
NODE_ROLE=host
FALLBACK_SSHD=1
```

This host still joins the tailnet the same way every other node does —
**without** `--ssh`, since it isn't serving Tailscale SSH:

```sh
sudo tailscale up
```

## 6. Verify with `doctor.sh`

```sh
./scripts/doctor.sh
```

With `FALLBACK_SSHD=1` and role `host` (or `both`), `doctor.sh`'s output
changes shape from the primary path:

- `tailscale-ssh-advertised` reads `SKIP` (this host doesn't advertise
  Tailscale SSH — that's expected and correct here, not a problem to fix).
- Three new checks run in its place: `sshd-running`, `sshd-hardening`, and
  `authorized-keys-perms`. All three must read `PASS`.

With `FALLBACK_SSHD=0` (the default, unset), the reverse is true: those three
checks `SKIP` and `tailscale-ssh-advertised` behaves exactly as it does on
every other host.

Don't re-derive these checks by hand — `doctor.sh` is still the single source
of truth for "is this node ready." Follow whatever fix hint it prints next to
any `FAIL` line, then re-run it.

## Reachability: tailnet-bounded, not a firewall rule

This fallback's sshd is reachable to anything on the tailnet's own address
(the `100.x.x.x` / `fd7a:...` tailnet interface) exactly like any other
service on the host — the same way it would be reachable on a LAN if the
tailnet interface were a LAN interface. Reachability here comes from the
tailnet's own boundary (only devices you've approved into the tailnet can
route to it at all), **not** from a `ListenAddress` binding in `sshd_config`
and **not** from any public port-forward. This guide never asks you to
pin `ListenAddress` to the tailnet interface, and never opens a port on a
public or LAN-facing interface. If you additionally want defense-in-depth
against some other process on this host binding a public listener, that's a
host-firewall concern outside this guide's scope — the four hardening
settings above are what makes this fallback safe to reach over the tailnet,
regardless of which interfaces sshd happens to listen on.

## Caveat: macOS may not show `sshd-running` until first connection

On some macOS versions, Remote Login's `sshd` is launched on demand by
`launchd` rather than running as a persistent background process — so
`doctor.sh`'s `sshd-running` check (which looks for a live `sshd` process)
can read `FAIL` immediately after you enable Remote Login, even though the
service is correctly configured and will start the moment a connection
arrives. If you hit this:

```sh
sudo launchctl list | grep -i ssh
```

A line for `com.openssh.sshd` confirms Remote Login is registered with
`launchd` and will spawn `sshd` on the first inbound connection. Trigger one
locally to make the process visible to `doctor.sh`:

```sh
ssh -o BatchMode=yes localhost exit || true
./scripts/doctor.sh
```

## 7. Enroll a client key

This section covers the **client** side: generating a key, delivering its
public half to the host, running `scripts/enroll.sh` there, and connecting
with `connect.sh --fallback`.

### Generate a client key (with a passphrase)

On the **client**, generate a dedicated ed25519 keypair for this fallback
(a separate key keeps this fallback's blast radius apart from any other
key you already use):

```sh
ssh-keygen -t ed25519 -C "<your-name>@<client-hostname>" -f ~/.ssh/id_ed25519_fallback
```

Set a real passphrase when prompted -- never leave it empty. Add the key to
your local `ssh-agent` so you aren't re-typing the passphrase on every
connection:

```sh
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_fallback
```

**Never copy the private key** (`id_ed25519_fallback`, no extension)
anywhere -- only the **public** half (`id_ed25519_fallback.pub`) ever
leaves this machine.

### Deliver the public key out-of-band

Get the `.pub` file's contents to the host over a channel you already
trust -- for example, over the tailnet itself:

```sh
tailscale file cp ~/.ssh/id_ed25519_fallback.pub <host-tailscale-name>:
```

On the host, accept it:

```sh
tailscale file get ~/
```

Any other out-of-band channel works too (pasting the one line over a chat
you already trust, etc.) -- it's a public key, not a secret, but it still
never belongs in a doc, commit, or issue in this repo.

### Run `enroll.sh` on the host

On the **host** (`NODE_ROLE=host` or `both`, `FALLBACK_SSHD=1` already set
per step 5 above):

```sh
./scripts/enroll.sh ~/id_ed25519_fallback.pub
```

or pipe it in:

```sh
cat ~/id_ed25519_fallback.pub | ./scripts/enroll.sh
```

`enroll.sh` appends the key to `~/.ssh/authorized_keys` only if an
equivalent key isn't already there, and fixes `~/.ssh`/`authorized_keys`
permissions every run. It refuses (exit 2, no side effects, and it never
prints the key) anything that isn't exactly one `ssh-ed25519` public key --
wrong key type, multiple keys, or garbage input. Re-running it with the
same key is safe: no duplicate line, no error. Re-enrolling the same key
material with a different comment does **not** update the stored comment --
the original line (and its original comment) is left as-is; to relabel an
entry, edit `~/.ssh/authorized_keys` by hand.

### Add the `Host` entry and connect

On the **client**, copy the `Host <node>` stanza from
[`config/ssh_config.example`](../config/ssh_config.example) into your own
`~/.ssh/config` (never committed to this repo), filling in the host's
tailnet name and the `<user>` account from step 2 above:

```
Host <node>
  HostName <node>
  User <user>
  ServerAliveInterval 15
  ServerAliveCountMax 3
```

Then connect the same way you would to any other workspace, adding
`--fallback`:

```sh
./scripts/connect.sh --fallback <node> <workspace>
```

This execs
`ssh -t <node> -- "$HOME/agentic-workstation/scripts/start-claude.sh" <workspace>`
-- the login user and any other connection options come entirely from your
`~/.ssh/config` entry, not from `SSH_USER`. Re-running the same command
reattaches to the existing session, exactly like the primary
`connect.sh <node> <workspace>` path.
