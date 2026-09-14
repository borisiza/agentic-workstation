#!/usr/bin/env bash
# connect.sh -- reach a workspace on a host with one command from a
# client node, or list which tailnet peers are online right now.
#
# Usage: connect.sh <node> <workspace>
#        connect.sh --fallback <node> <workspace>
#        connect.sh
#        connect.sh --check
#        connect.sh -h|--help
#
# Requires NODE_ROLE=client|both (config/local.env -> $NODE_ROLE, same
# precedence as doctor.sh/start-claude.sh); NODE_ROLE=host exits 2 before
# any tailscale call. With <node> <workspace>, validates <workspace>
# against [a-z0-9-]+, resolves the SSH login user from SSH_USER in
# config/local.env (default: current login user, never root), then execs:
#   tailscale ssh -t <user>@<node> -- "$HOME/agentic-workstation/scripts/start-claude.sh" <workspace>
# using the absolute repo path (expanded remotely, by convention every
# node clones the repo to $HOME/agentic-workstation) since a non-interactive
# tailscale ssh command never sources the remote login profile. Re-running
# the same command reattaches -- delegated entirely to start-claude.sh's
# own idempotent attach-or-create logic. With --fallback <node> <workspace>
# (for a host using the documented OpenSSH fallback, docs/fallback-openssh.md),
# execs plain ssh instead of tailscale ssh:
#   ssh -t <node> -- "$HOME/agentic-workstation/scripts/start-claude.sh" <workspace>
# relying entirely on the client's own untracked ~/.ssh/config (see
# config/ssh_config.example) for the login user and connection options --
# this mode never reads SSH_USER and never calls tailscale, and it never
# probes for or lists fallback hosts. With no arguments, lists tailnet
# peers currently online, parsed live from `tailscale status` text only --
# never persisted to a file. Never prints tokens, keys, tailnet IPs, or
# node names beyond the hostnames `tailscale status` itself prints. See
# config/local.env.example for the config file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]:-$0}")"
CONFIG_FILE="${DOCTOR_CONFIG_FILE:-$SCRIPT_DIR/../config/local.env}"

ROLE=""

usage() {
  cat <<'EOF'
Usage: connect.sh <node> <workspace>
       connect.sh --fallback <node> <workspace>
       connect.sh
       connect.sh --check
       connect.sh -h|--help

With <node> and <workspace>, execs into the host's persistent Claude Code
session for that workspace:
  tailscale ssh -t <user>@<node> -- "$HOME/agentic-workstation/scripts/start-claude.sh" <workspace>
<user> comes from SSH_USER (config/local.env), defaulting to the current
login user; root is refused. Re-running the same command reattaches
(scrollback intact) instead of starting a second session.

With --fallback <node> <workspace>, execs plain ssh instead of
tailscale ssh, for a host using the documented OpenSSH fallback (see
docs/fallback-openssh.md):
  ssh -t <node> -- "$HOME/agentic-workstation/scripts/start-claude.sh" <workspace>
The login user and any other connection options come entirely from your
own ~/.ssh/config Host <node> entry (see config/ssh_config.example) --
this mode never reads SSH_USER and never calls tailscale.

With no arguments, lists tailnet peers that are currently online, parsed
live from `tailscale status` -- nothing is ever written to a file.

Requires NODE_ROLE=client or NODE_ROLE=both (config/local.env ->
$NODE_ROLE).

  --check   run connect.sh's own side-effect-free self-test and exit
  -h --help show this help
EOF
}

die2() {
  printf '%s\n' "$1" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

validate_workspace_name() {
  local ws="$1"
  local LC_ALL=C
  case "$ws" in
    "")
      die2 "Missing workspace name: usage: connect.sh <node> <workspace>."
      ;;
    *[!a-z0-9-]*)
      die2 "Invalid workspace name '$ws': must match [a-z0-9-]+."
      ;;
  esac
}

# Mirrors start-claude.sh's resolve_and_validate_role: config/local.env (if
# present) wins, then falls back to the inherited $NODE_ROLE env var.
# Requires client|both -- the inverse of start-claude.sh's host|both.
resolve_and_validate_role() {
  if [ -f "$CONFIG_FILE" ]; then
    local source_rc=0
    set +eu
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
    source_rc=$?
    set -eu
    if [ "$source_rc" -ne 0 ]; then
      die2 "config/local.env failed to load: fix its syntax or restore it from config/local.env.example."
    fi
  fi

  ROLE="${NODE_ROLE:-}"
  case "$ROLE" in
    client | both)
      ;;
    *)
      die2 "connect.sh requires NODE_ROLE=client or NODE_ROLE=both (set it in config/local.env or export NODE_ROLE)."
      ;;
  esac
}

# resolve_ssh_user -- SSH_USER from config/local.env (already sourced by
# resolve_and_validate_role), defaulting to the current login user; root
# is always refused.
resolve_ssh_user() {
  CONNECT_USER="${SSH_USER:-}"
  if [ -z "$CONNECT_USER" ]; then
    CONNECT_USER="${LOGNAME:-$(id -un)}"
  fi
  if [ "$CONNECT_USER" = "root" ]; then
    die2 "connect.sh refuses to connect as root: set SSH_USER to a non-root user in config/local.env."
  fi
}

# ---------------------------------------------------------------------------
# Connect mode
# ---------------------------------------------------------------------------

connect() {
  local node="$1" ws="$2"
  if [ -z "$node" ]; then
    die2 "Missing node name: usage: connect.sh <node> <workspace>."
  fi
  validate_workspace_name "$ws"
  resolve_ssh_user
  # '$HOME/...' is single-quoted so it is expanded by the *remote* shell
  # (every node clones this repo to $HOME/agentic-workstation by
  # convention), never by this local shell -- SSH_USER's home directory
  # may differ from ours.
  # shellcheck disable=SC2016
  exec tailscale ssh -t "${CONNECT_USER}@${node}" -- '$HOME/agentic-workstation/scripts/start-claude.sh' "$ws"
}

# ---------------------------------------------------------------------------
# Fallback connect mode (plain ssh, no tailscale, no SSH_USER)
# ---------------------------------------------------------------------------

# fallback_connect NODE WORKSPACE -- for a host using the documented
# OpenSSH fallback (docs/fallback-openssh.md). Never probes for or lists
# fallback hosts, and never touches resolve_ssh_user/SSH_USER: the login
# user and any other connection options come entirely from the client's
# own untracked ~/.ssh/config Host <node> stanza (config/ssh_config.example).
fallback_connect() {
  local node="$1" ws="$2"
  if [ -z "$node" ]; then
    die2 "Missing node name: usage: connect.sh --fallback <node> <workspace>."
  fi
  case "$node" in
    -*)
      die2 "Invalid node name '$node': must not start with '-' (looks like an option)."
      ;;
  esac
  validate_workspace_name "$ws"
  # '$HOME/...' is single-quoted so it is expanded by the *remote* shell,
  # matching connect()'s own convention -- see that function's comment.
  # shellcheck disable=SC2016
  exec ssh -t "$node" -- '$HOME/agentic-workstation/scripts/start-claude.sh' "$ws"
}

# ---------------------------------------------------------------------------
# Discovery mode
# ---------------------------------------------------------------------------

# discover_peers -- parses live `tailscale status` text (no jq/awk): skips
# line 1 (self), skips any line whose last whitespace-separated field
# case-insensitively equals "offline", prints field 2 (hostname) for the
# rest. Never persists the list to a file. Fails cleanly (exit 2) if the
# tailscaled backend itself isn't running, instead of misreporting "no
# peers" (mirrors doctor.sh's check_tailnet_membership first-line check).
discover_peers() {
  local out
  if ! out="$(tailscale status 2>&1)"; then
    die2 "tailscale status failed: is tailscaled running? (run: tailscale up)"
  fi
  if printf '%s\n' "$out" | head -n1 | grep -qiE 'stopped|logged out|needs login|not running'; then
    die2 "tailscale backend is not running (run: tailscale up)."
  fi

  printf '%s\n' "$out" | tail -n +2 | while IFS= read -r line; do
    [ -n "$line" ] || continue
    # Intentional word-splitting to tokenize the status line on whitespace,
    # with globbing disabled so a stray *, ?, or [ in a field can't expand
    # against filenames in the current directory.
    set -f
    # shellcheck disable=SC2086
    set -- $line
    set +f
    [ $# -ge 2 ] || continue
    host="$2"
    last=""
    for last in "$@"; do :; done
    case "$last" in
      [Oo][Ff][Ff][Ll][Ii][Nn][Ee])
        continue
        ;;
    esac
    printf '%s\n' "$host"
  done
}

# ---------------------------------------------------------------------------
# --check self-test: fully sandboxed, deterministic, side-effect-free.
# ---------------------------------------------------------------------------

write_stub_tools() {
  local bin_dir="$1"

  cat >"$bin_dir/tailscale" <<'EOF'
#!/usr/bin/env bash
# Records every subcommand invoked (so the self-test can prove certain
# code paths never call tailscale at all) and fakes `status`/`ssh`
# instead of touching the real network.
if [ -n "${CONNECT_STUB_CALL_LOG:-}" ]; then
  printf '%s\n' "${1:-}" >>"$CONNECT_STUB_CALL_LOG"
fi
case "${1:-}" in
  status)
    case "${CONNECT_STUB_TS_STATE:-running}" in
      stopped)
        printf 'Tailscale is stopped.\n'
        ;;
      down)
        exit 1
        ;;
      onlyself)
        printf '100.64.0.1   self-node    user@   linux   -\n'
        ;;
      *)
        printf '100.64.0.1   self-node    user@   linux   -\n'
        printf '100.64.0.2   host1        user@   linux   -\n'
        printf '100.64.0.3   host2        user@   linux   offline\n'
        ;;
    esac
    ;;
  ssh)
    shift
    if [ -n "${CONNECT_STUB_SSH_ARGV_FILE:-}" ]; then
      printf '%s\n' "$@" >"$CONNECT_STUB_SSH_ARGV_FILE"
    fi
    exit "${CONNECT_STUB_SSH_EXIT_CODE:-0}"
    ;;
  *)
    exit 0
    ;;
esac
EOF

  chmod +x "$bin_dir/tailscale"

  cat >"$bin_dir/ssh" <<'EOF'
#!/usr/bin/env bash
# Fakes plain `ssh` for --fallback mode: records argv instead of opening a
# real connection, so the self-test never calls tailscale for this path.
if [ -n "${CONNECT_STUB_PLAIN_SSH_ARGV_FILE:-}" ]; then
  printf '%s\n' "$@" >"$CONNECT_STUB_PLAIN_SSH_ARGV_FILE"
fi
exit "${CONNECT_STUB_PLAIN_SSH_EXIT_CODE:-0}"
EOF

  chmod +x "$bin_dir/ssh"
}

assert_exit_eq() {
  local case_name="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    printf 'self-test FAILED [%s]: expected exit %s, got %s\n' "$case_name" "$expected" "$actual" >&2
    return 1
  fi
  return 0
}

assert_stderr_one_line() {
  local case_name="$1" errfile="$2" n
  n="$(grep -c . "$errfile" 2>/dev/null || true)"
  n="${n:-0}"
  if [ "$n" -ne 1 ]; then
    printf 'self-test FAILED [%s]: expected exactly 1 stderr line, got %s\n' "$case_name" "$n" >&2
    return 1
  fi
  return 0
}

assert_file_absent() {
  local case_name="$1" file="$2"
  if [ -e "$file" ]; then
    printf 'self-test FAILED [%s]: expected %s to not exist\n' "$case_name" "$file" >&2
    return 1
  fi
  return 0
}

assert_file_contains() {
  local case_name="$1" file="$2" pattern="$3"
  if [ ! -f "$file" ] || ! grep -Fq -- "$pattern" "$file"; then
    printf 'self-test FAILED [%s]: expected %s to contain: %s\n' "$case_name" "$file" "$pattern" >&2
    return 1
  fi
  return 0
}

assert_stdout_contains() {
  local case_name="$1" file="$2" pattern="$3"
  if ! grep -Eq "$pattern" "$file"; then
    printf 'self-test FAILED [%s]: expected stdout to match: %s\n' "$case_name" "$pattern" >&2
    return 1
  fi
  return 0
}

assert_stdout_not_contains() {
  local case_name="$1" file="$2" pattern="$3"
  if grep -Eq "$pattern" "$file"; then
    printf 'self-test FAILED [%s]: stdout unexpectedly matched: %s\n' "$case_name" "$pattern" >&2
    return 1
  fi
  return 0
}

assert_empty_file() {
  local case_name="$1" file="$2"
  if [ -s "$file" ]; then
    printf 'self-test FAILED [%s]: expected %s to be empty\n' "$case_name" "$file" >&2
    return 1
  fi
  return 0
}

# assert_file_exact_lines CASE FILE LINE... -- fails unless FILE's lines
# match LINE... exactly, in order (catches an argv whose elements are all
# present but reordered, which independent assert_file_contains calls
# would miss).
assert_file_exact_lines() {
  local case_name="$1" file="$2"
  shift 2
  if [ ! -f "$file" ]; then
    printf 'self-test FAILED [%s]: expected %s to exist\n' "$case_name" "$file" >&2
    return 1
  fi
  if ! diff -q <(printf '%s\n' "$@") "$file" >/dev/null 2>&1; then
    printf 'self-test FAILED [%s]: %s did not match the expected argv, in order\n' "$case_name" "$file" >&2
    printf '  expected:\n' >&2
    printf '%s\n' "$@" | sed 's/^/    /' >&2
    printf '  actual:\n' >&2
    sed 's/^/    /' "$file" >&2
    return 1
  fi
  return 0
}

selftest_case_connect_fresh() {
  local sandbox="$1" stub_path="$2"
  local case_name="connect-fresh"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/ssh-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client SSH_USER=alice \
    CONNECT_STUB_SSH_ARGV_FILE="$argv" \
    "$SCRIPT_PATH" host1 demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  # shellcheck disable=SC2016
  assert_file_exact_lines "$case_name" "$argv" \
    "-t" "alice@host1" "--" '$HOME/agentic-workstation/scripts/start-claude.sh' "demo" || ok=1
  return "$ok"
}

selftest_case_connect_default_user() {
  local sandbox="$1" stub_path="$2"
  local case_name="connect-default-user"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/ssh-argv" rc=0 ok=0 expected_user
  expected_user="$(id -un)"
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=both \
    CONNECT_STUB_SSH_ARGV_FILE="$argv" \
    "$SCRIPT_PATH" host1 demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  # shellcheck disable=SC2016
  assert_file_exact_lines "$case_name" "$argv" \
    "-t" "${expected_user}@host1" "--" '$HOME/agentic-workstation/scripts/start-claude.sh' "demo" || ok=1
  return "$ok"
}

selftest_case_connect_ssh_user_from_config() {
  local sandbox="$1" stub_path="$2"
  local case_name="connect-ssh-user-from-config"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  printf 'NODE_ROLE=client\nSSH_USER=bob\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" argv="$dir/ssh-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/local.env" \
    CONNECT_STUB_SSH_ARGV_FILE="$argv" \
    "$SCRIPT_PATH" host1 demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  # shellcheck disable=SC2016
  assert_file_exact_lines "$case_name" "$argv" \
    "-t" "bob@host1" "--" '$HOME/agentic-workstation/scripts/start-claude.sh' "demo" || ok=1
  return "$ok"
}

selftest_case_discovery_mixed() {
  local sandbox="$1" stub_path="$2"
  local case_name="discovery-mixed"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    CONNECT_STUB_TS_STATE=running \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_contains "$case_name" "$out" '^host1$' || ok=1
  assert_stdout_not_contains "$case_name" "$out" '^host2$' || ok=1
  assert_stdout_not_contains "$case_name" "$out" '^self-node$' || ok=1
  return "$ok"
}

selftest_case_discovery_no_peers() {
  local sandbox="$1" stub_path="$2"
  local case_name="discovery-no-peers"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    CONNECT_STUB_TS_STATE=onlyself \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_empty_file "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_discovery_backend_down() {
  local sandbox="$1" stub_path="$2"
  local case_name="discovery-backend-down"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    CONNECT_STUB_TS_STATE=stopped \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  return "$ok"
}

selftest_case_wrong_role() {
  local sandbox="$1" stub_path="$2"
  local case_name="wrong-role"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/ssh-argv" log="$dir/call-log" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    CONNECT_STUB_SSH_ARGV_FILE="$argv" CONNECT_STUB_CALL_LOG="$log" \
    "$SCRIPT_PATH" host1 demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  assert_file_absent "$case_name" "$log" || ok=1
  return "$ok"
}

# Proves the role gate blocks the zero-arg discovery path too, not just
# the two-arg connect path (AD-1: NODE_ROLE=host exits 2 before any
# tailscale call, for the script as a whole).
selftest_case_wrong_role_discovery() {
  local sandbox="$1" stub_path="$2"
  local case_name="wrong-role-discovery"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" log="$dir/call-log" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    CONNECT_STUB_CALL_LOG="$log" \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$log" || ok=1
  return "$ok"
}

selftest_case_missing_role() {
  local sandbox="$1" stub_path="$2"
  local case_name="missing-role"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  return "$ok"
}

# Mirrors start-claude.sh/status.sh/stop.sh's broken-config case: a
# config/local.env that exists but fails to source must exit 2 with a
# diagnostic naming the config file, before the role check even runs, and
# before any tailscale call.
selftest_case_broken_config() {
  local sandbox="$1" stub_path="$2"
  local case_name="broken-config"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  printf 'NODE_ROLE=client\nif [ \n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" argv="$dir/ssh-argv" log="$dir/call-log" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/local.env" \
    CONNECT_STUB_SSH_ARGV_FILE="$argv" CONNECT_STUB_CALL_LOG="$log" \
    "$SCRIPT_PATH" host1 demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_file_contains "$case_name" "$err" "config/local.env" || ok=1
  assert_file_contains "$case_name" "$err" "syntax error" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  assert_file_absent "$case_name" "$log" || ok=1
  return "$ok"
}

selftest_case_bad_workspace_name() {
  local sandbox="$1" stub_path="$2"
  local case_name="bad-workspace-name"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/ssh-argv" log="$dir/call-log" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    CONNECT_STUB_SSH_ARGV_FILE="$argv" CONNECT_STUB_CALL_LOG="$log" \
    "$SCRIPT_PATH" host1 "Bad Name!" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  assert_file_absent "$case_name" "$log" || ok=1
  return "$ok"
}

selftest_case_root_ssh_user() {
  local sandbox="$1" stub_path="$2"
  local case_name="root-ssh-user"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/ssh-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client SSH_USER=root \
    CONNECT_STUB_SSH_ARGV_FILE="$argv" \
    "$SCRIPT_PATH" host1 demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

selftest_case_missing_workspace_arg() {
  local sandbox="$1" stub_path="$2"
  local case_name="missing-workspace-arg"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    "$SCRIPT_PATH" host1 >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  return "$ok"
}

selftest_case_too_many_args() {
  local sandbox="$1" stub_path="$2"
  local case_name="too-many-args"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    "$SCRIPT_PATH" host1 demo extra >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  return "$ok"
}

selftest_case_help() {
  local sandbox="$1" stub_path="$2"
  local case_name="help"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    "$SCRIPT_PATH" --help >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_file_contains "$case_name" "$out" "Usage: connect.sh" || ok=1
  return "$ok"
}

selftest_case_fallback_happy_path() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-happy-path"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/plain-ssh-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    CONNECT_STUB_PLAIN_SSH_ARGV_FILE="$argv" \
    "$SCRIPT_PATH" --fallback fallbackhost demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  # shellcheck disable=SC2016
  assert_file_exact_lines "$case_name" "$argv" \
    "-t" "fallbackhost" "--" '$HOME/agentic-workstation/scripts/start-claude.sh' "demo" || ok=1
  return "$ok"
}

# Proves --fallback never touches SSH_USER/resolve_ssh_user: even with
# SSH_USER set, the exec'd ssh argv carries only <node> -- the login user
# comes entirely from the client's own ~/.ssh/config Host <node> entry.
selftest_case_fallback_ignores_ssh_user() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-ignores-ssh-user"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/plain-ssh-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client SSH_USER=alice \
    CONNECT_STUB_PLAIN_SSH_ARGV_FILE="$argv" \
    "$SCRIPT_PATH" --fallback fallbackhost demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  # shellcheck disable=SC2016
  assert_file_exact_lines "$case_name" "$argv" \
    "-t" "fallbackhost" "--" '$HOME/agentic-workstation/scripts/start-claude.sh' "demo" || ok=1
  return "$ok"
}

selftest_case_fallback_bad_workspace_name() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-bad-workspace-name"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/plain-ssh-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    CONNECT_STUB_PLAIN_SSH_ARGV_FILE="$argv" \
    "$SCRIPT_PATH" --fallback fallbackhost "Bad Name!" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

selftest_case_fallback_wrong_arg_count() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-wrong-arg-count"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/plain-ssh-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    CONNECT_STUB_PLAIN_SSH_ARGV_FILE="$argv" \
    "$SCRIPT_PATH" --fallback fallbackhost >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

# Proves fallback_connect() rejects a <node> that looks like an ssh option
# (e.g. a crafted/mistyped -oProxyCommand=... value) instead of passing it
# through unguarded, which would let ssh parse it as an option rather than
# a hostname.
selftest_case_fallback_node_looks_like_option() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-node-looks-like-option"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/plain-ssh-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    CONNECT_STUB_PLAIN_SSH_ARGV_FILE="$argv" \
    "$SCRIPT_PATH" --fallback -oProxyCommand=evil demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

selftest_case_fallback_wrong_role() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-wrong-role"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/plain-ssh-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    CONNECT_STUB_PLAIN_SSH_ARGV_FILE="$argv" \
    "$SCRIPT_PATH" --fallback fallbackhost demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

# Proves connect.sh without --fallback is byte-for-byte unchanged (AD-3):
# still execs `tailscale ssh` and never touches the new plain-ssh stub,
# even though both stubs are now on PATH.
selftest_case_fallback_flag_absent_unchanged() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-flag-absent-unchanged"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" ts_argv="$dir/ssh-argv" plain_argv="$dir/plain-ssh-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client SSH_USER=alice \
    CONNECT_STUB_SSH_ARGV_FILE="$ts_argv" CONNECT_STUB_PLAIN_SSH_ARGV_FILE="$plain_argv" \
    "$SCRIPT_PATH" host1 demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  # shellcheck disable=SC2016
  assert_file_exact_lines "$case_name" "$ts_argv" \
    "-t" "alice@host1" "--" '$HOME/agentic-workstation/scripts/start-claude.sh' "demo" || ok=1
  assert_file_absent "$case_name" "$plain_argv" || ok=1
  return "$ok"
}

run_self_test() {
  # Deliberately not `local`: the EXIT trap below must still see it after
  # this function returns (bash pops `local`s before the trap fires).
  local tmpdir="${TMPDIR:-/tmp}"
  tmpdir="${tmpdir%/}"
  SELFTEST_SANDBOX="$(mktemp -d "$tmpdir/connect-selftest.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$SELFTEST_SANDBOX'" EXIT

  local bin_dir="$SELFTEST_SANDBOX/bin" stub_path overall_rc=0
  mkdir -p "$bin_dir"
  write_stub_tools "$bin_dir"
  stub_path="$bin_dir:/usr/bin:/bin"

  selftest_case_connect_fresh "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_connect_default_user "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_connect_ssh_user_from_config "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_discovery_mixed "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_discovery_no_peers "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_discovery_backend_down "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_wrong_role "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_wrong_role_discovery "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_missing_role "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_broken_config "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_bad_workspace_name "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_root_ssh_user "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_missing_workspace_arg "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_too_many_args "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_help "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_happy_path "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_ignores_ssh_user "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_bad_workspace_name "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_node_looks_like_option "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_wrong_arg_count "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_wrong_role "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_flag_absent_unchanged "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1

  if [ "$overall_rc" -eq 0 ]; then
    printf 'PASS  self-test -- all connect.sh --check assertions passed\n'
  else
    printf 'FAIL  self-test -- one or more --check assertions failed (see stderr)\n' >&2
  fi
  return "$overall_rc"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

main() {
  if [ $# -eq 1 ] && [ "$1" = "--check" ]; then
    run_self_test
    exit $?
  fi

  if [ $# -eq 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
    usage
    exit 0
  fi

  resolve_and_validate_role

  if [ $# -ge 1 ] && [ "$1" = "--fallback" ]; then
    if [ $# -ne 3 ]; then
      die2 "Usage: connect.sh --fallback <node> <workspace> (see --help)"
    fi
    fallback_connect "$2" "$3"
    return
  fi

  case $# in
    0)
      discover_peers
      exit 0
      ;;
    2)
      connect "$1" "$2"
      ;;
    *)
      die2 "Usage: connect.sh [<node> <workspace>] (see --help)"
      ;;
  esac
}

main "$@"
