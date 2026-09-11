#!/usr/bin/env bash
# doctor.sh -- resolve this node's role and verify it is ready to join the mesh.
#
# Usage: doctor.sh [--role host|client|both] [--check] [-h|--help]
#
# Role resolution order: config/local.env (if present, wins) -> $NODE_ROLE
# env var -> --role flag (lowest-precedence fallback, only used when neither
# the config file nor the env var set a role). Runs one PASS|FAIL|SKIP check
# per requirement: common checks for
# any valid role, host-only checks for host|both (client SKIPs them).
# Exits 0 only when no check is FAIL. Never prints tokens, keys, tailnet
# IPs, or node names. See config/local.env.example for the config file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]:-$0}")"
CONFIG_FILE="${DOCTOR_CONFIG_FILE:-$SCRIPT_DIR/../config/local.env}"

FAIL_COUNT=0
ROLE=""
ROLE_FLAG=""
RUN_CHECK=0

usage() {
  cat <<'EOF'
Usage: doctor.sh [--role host|client|both] [--check] [-h|--help]

Verifies this node is ready to join the mesh: resolves NODE_ROLE
(config/local.env -> $NODE_ROLE -> --role), then runs PASS/FAIL/SKIP
checks for required tools, tailnet membership, ~/.ssh permissions,
and (for host|both) the host-only platform contract.

  --role R  role hint used only if config/local.env and $NODE_ROLE
            are both unset (reserved for a future story)
  --check   run doctor.sh's own side-effect-free self-test and exit
  -h --help show this help
EOF
}

die2() {
  printf '%s\n' "$1" >&2
  exit 2
}

emit() {
  local status="$1" name="$2" detail="$3"
  if [ -n "$detail" ]; then
    printf '%s  %s -- %s\n' "$status" "$name" "$detail"
  else
    printf '%s  %s\n' "$status" "$name"
  fi
  if [ "$status" = "FAIL" ]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ver_ge HAVE WANT -- true if dotted version HAVE >= WANT (major.minor.patch).
ver_ge() {
  local have="$1" want="$2"
  local h_maj h_min h_pat w_maj w_min w_pat
  h_maj="$(printf '%s' "$have" | cut -d. -f1 | sed 's/[^0-9].*//')"; h_maj="${h_maj:-0}"
  h_min="$(printf '%s' "$have" | cut -d. -f2 | sed 's/[^0-9].*//')"; h_min="${h_min:-0}"
  h_pat="$(printf '%s' "$have" | cut -d. -f3 | sed 's/[^0-9].*//')"; h_pat="${h_pat:-0}"
  w_maj="$(printf '%s' "$want" | cut -d. -f1 | sed 's/[^0-9].*//')"; w_maj="${w_maj:-0}"
  w_min="$(printf '%s' "$want" | cut -d. -f2 | sed 's/[^0-9].*//')"; w_min="${w_min:-0}"
  w_pat="$(printf '%s' "$want" | cut -d. -f3 | sed 's/[^0-9].*//')"; w_pat="${w_pat:-0}"

  if [ "$h_maj" -gt "$w_maj" ]; then return 0; fi
  if [ "$h_maj" -lt "$w_maj" ]; then return 1; fi
  if [ "$h_min" -gt "$w_min" ]; then return 0; fi
  if [ "$h_min" -lt "$w_min" ]; then return 1; fi
  [ "$h_pat" -ge "$w_pat" ]
}

# octal_mode PATH -- portable (GNU or BSD) file mode as three octal digits.
octal_mode() {
  local path="$1"
  if stat -c '%a' "$path" >/dev/null 2>&1; then
    stat -c '%a' "$path"
  else
    stat -f '%Lp' "$path"
  fi
}

# ---------------------------------------------------------------------------
# Role resolution
# ---------------------------------------------------------------------------

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
  if [ -z "$ROLE" ]; then
    ROLE="$ROLE_FLAG"
  fi

  case "$ROLE" in
    host | client | both)
      ;;
    "")
      die2 "Missing NODE_ROLE: copy config/local.env.example to config/local.env and set NODE_ROLE to host, client, or both."
      ;;
    *)
      die2 "Invalid NODE_ROLE '$ROLE': must be host, client, or both."
      ;;
  esac

  WORKSPACES_DIR="${WORKSPACES_DIR:-$HOME/workspaces}"
}

# ---------------------------------------------------------------------------
# Common checks (any valid role)
# ---------------------------------------------------------------------------

check_command() {
  local label="$1" bin="$2" hint="$3"
  if command -v "$bin" >/dev/null 2>&1; then
    emit PASS "$label" ""
  else
    emit FAIL "$label" "$hint"
  fi
}

check_tailscale_installed() {
  if ! command -v tailscale >/dev/null 2>&1; then
    emit FAIL "tailscale-installed" "install tailscale: https://tailscale.com/download"
    return
  fi
  local raw ver
  raw="$(tailscale version 2>/dev/null | head -n1 || true)"
  ver="$(printf '%s' "$raw" | cut -d' ' -f1)"
  if ver_ge "$ver" "1.102.0"; then
    emit PASS "tailscale-installed" "version $ver"
  else
    emit FAIL "tailscale-installed" "upgrade tailscale to >=1.102 (found ${ver:-unknown})"
  fi
}

check_tailnet_membership() {
  if ! command -v tailscale >/dev/null 2>&1; then
    emit SKIP "tailnet-membership" "tailscale not installed"
    return
  fi
  local out
  if ! out="$(tailscale status 2>&1)"; then
    emit FAIL "tailnet-membership" "run: tailscale up"
    return
  fi
  if printf '%s' "$out" | head -n1 | grep -qiE 'stopped|logged out|needs login|not running'; then
    emit FAIL "tailnet-membership" "run: tailscale up"
    return
  fi
  emit PASS "tailnet-membership" "backend Running"
}

check_ssh_dir_perms() {
  local ssh_dir="$HOME/.ssh"
  if [ ! -d "$ssh_dir" ]; then
    emit FAIL "ssh-dir-perms" "create $ssh_dir and run: chmod 700 $ssh_dir"
    return
  fi
  local mode
  mode="$(octal_mode "$ssh_dir")"
  if [ "$mode" = "700" ]; then
    emit PASS "ssh-dir-perms" ""
  else
    emit FAIL "ssh-dir-perms" "run: chmod 700 $ssh_dir (found $mode)"
  fi
}

check_ssh_key_perms() {
  local ssh_dir="$HOME/.ssh"
  if [ ! -d "$ssh_dir" ]; then
    emit SKIP "ssh-key-perms" "no ~/.ssh directory"
    return
  fi
  local f mode found=0 bad=0
  for f in "$ssh_dir"/id_*; do
    [ -e "$f" ] || continue
    case "$f" in
      *.pub) continue ;;
    esac
    found=1
    mode="$(octal_mode "$f")"
    if [ "$mode" != "600" ]; then
      bad=1
    fi
  done
  if [ "$found" -eq 0 ]; then
    emit SKIP "ssh-key-perms" "no id_* private keys found"
  elif [ "$bad" -eq 1 ]; then
    emit FAIL "ssh-key-perms" "run: chmod 600 ~/.ssh/id_*"
  else
    emit PASS "ssh-key-perms" ""
  fi
}

run_common_checks() {
  check_tailscale_installed
  check_tailnet_membership
  check_command "tmux-installed" "tmux" "install tmux"
  check_command "claude-installed" "claude" "install claude (Claude Code CLI)"
  check_command "git-installed" "git" "install git"
  check_ssh_dir_perms
  check_ssh_key_perms
}

# ---------------------------------------------------------------------------
# Host-only checks (role host|both); client SKIPs these
# ---------------------------------------------------------------------------

check_tailscale_ssh_advertised() {
  if ! command -v tailscale >/dev/null 2>&1; then
    emit SKIP "tailscale-ssh-advertised" "tailscale not installed"
    return
  fi
  local prefs
  if ! prefs="$(tailscale debug prefs 2>/dev/null)"; then
    emit FAIL "tailscale-ssh-advertised" "run: tailscale up --ssh"
    return
  fi
  if printf '%s' "$prefs" | grep -Eq '"RunSSH"[[:space:]]*:[[:space:]]*true'; then
    emit PASS "tailscale-ssh-advertised" ""
  else
    emit FAIL "tailscale-ssh-advertised" "run: tailscale up --ssh"
  fi
}

check_workspaces_dir() {
  local dir="${WORKSPACES_DIR:-$HOME/workspaces}"
  if [ -d "$dir" ]; then
    emit PASS "workspaces-dir" ""
  else
    emit FAIL "workspaces-dir" "create it: mkdir -p \"$dir\" (or set WORKSPACES_DIR)"
  fi
}

is_wsl() {
  if [ -n "${WSL_DISTRO_NAME:-}" ]; then
    return 0
  fi
  if [ -r /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
    return 0
  fi
  return 1
}

check_macos_backend() {
  local line path
  line="$(pgrep -fl tailscaled 2>/dev/null | head -n1 || true)"
  if [ -z "$line" ]; then
    emit FAIL "platform-contract" "start Homebrew tailscaled: brew services start tailscale"
    return
  fi
  path="${line#* }"
  case "$path" in
    /opt/homebrew/* | /usr/local/*)
      emit PASS "platform-contract" "Homebrew tailscaled active"
      ;;
    *)
      emit FAIL "platform-contract" "switch from the Tailscale GUI app to Homebrew tailscaled: brew install tailscale && brew services start tailscale"
      ;;
  esac
}

check_wsl_pid1() {
  local comm
  comm="$(ps -p 1 -o comm= 2>/dev/null || true)"
  if [ "$comm" = "systemd" ]; then
    emit PASS "platform-contract" "systemd is PID 1"
  else
    emit FAIL "platform-contract" "enable systemd in /etc/wsl.conf ([boot] systemd=true) and restart the distro"
  fi
}

check_platform_contract() {
  local os
  os="$(uname -s)"
  case "$os" in
    Darwin)
      check_macos_backend
      ;;
    Linux)
      if is_wsl; then
        check_wsl_pid1
      else
        emit SKIP "platform-contract" "native Linux host: no additional contract check"
      fi
      ;;
    *)
      emit SKIP "platform-contract" "unrecognized platform: $os"
      ;;
  esac
}

run_host_checks() {
  case "$ROLE" in
    host | both)
      check_tailscale_ssh_advertised
      check_workspaces_dir
      check_platform_contract
      ;;
    client)
      emit SKIP "tailscale-ssh-advertised" "client role"
      emit SKIP "workspaces-dir" "client role"
      emit SKIP "platform-contract" "client role"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# --check self-test: fully sandboxed, deterministic, side-effect-free.
# ---------------------------------------------------------------------------

write_stub_tools() {
  local bin_dir="$1"

  cat >"$bin_dir/tailscale" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  version)
    printf '%s\n' "${DOCTOR_STUB_TS_VERSION:-1.150.0}"
    ;;
  status)
    case "${DOCTOR_STUB_TS_STATE:-running}" in
      stopped) printf 'Tailscale is stopped.\n' ;;
      down) exit 1 ;;
      *) printf 'TEST-SELF test-node test-user linux -\n' ;;
    esac
    ;;
  debug)
    if [ "${DOCTOR_STUB_TS_SSH:-1}" = "1" ]; then
      printf '{"RunSSH": true}\n'
    else
      printf '{"RunSSH": false}\n'
    fi
    ;;
  *)
    exit 0
    ;;
esac
EOF

  cat >"$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'tmux 3.4\n'
EOF

  cat >"$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
printf '1.0.0 (Claude Code)\n'
EOF

  cat >"$bin_dir/git" <<'EOF'
#!/usr/bin/env bash
printf 'git version 2.43.0\n'
EOF

  cat >"$bin_dir/uname" <<'EOF'
#!/usr/bin/env bash
if [ -n "${DOCTOR_STUB_UNAME:-}" ]; then
  printf '%s\n' "$DOCTOR_STUB_UNAME"
  exit 0
fi
exec /usr/bin/uname "$@"
EOF

  cat >"$bin_dir/pgrep" <<'EOF'
#!/usr/bin/env bash
if [ -n "${DOCTOR_STUB_TAILSCALED_PATH:-}" ]; then
  printf '4242 %s\n' "$DOCTOR_STUB_TAILSCALED_PATH"
  exit 0
fi
exit 1
EOF

  cat >"$bin_dir/ps" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"-p 1"*)
    if [ -n "${DOCTOR_STUB_PID1:-}" ]; then
      printf '%s\n' "$DOCTOR_STUB_PID1"
      exit 0
    fi
    ;;
esac
exec /bin/ps "$@"
EOF

  chmod +x "$bin_dir"/tailscale "$bin_dir"/tmux "$bin_dir"/claude "$bin_dir"/git \
    "$bin_dir"/uname "$bin_dir"/pgrep "$bin_dir"/ps
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

assert_no_leak() {
  local case_name="$1" file="$2"
  if grep -Eq '100\.[0-9]+\.[0-9]+\.[0-9]+|fd7a:' "$file"; then
    printf 'self-test FAILED [%s]: possible tailnet IP leak in %s\n' "$case_name" "$file" >&2
    return 1
  fi
  return 0
}

selftest_case_missing_config() {
  local sandbox="$1" stub_path="$2"
  local case_name="missing-config"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  assert_no_leak "$case_name" "$err" || ok=1
  return "$ok"
}

selftest_case_invalid_role() {
  local sandbox="$1" stub_path="$2"
  local case_name="invalid-role"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  printf 'NODE_ROLE=bogus\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/local.env" \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  return "$ok"
}

selftest_case_valid_client() {
  local sandbox="$1" stub_path="$2"
  local case_name="valid-client"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  : >"$dir/home/.ssh/id_ed25519"
  chmod 600 "$dir/home/.ssh/id_ed25519"
  : >"$dir/home/.ssh/id_ed25519.pub"
  chmod 644 "$dir/home/.ssh/id_ed25519.pub"
  printf 'NODE_ROLE=client\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_not_contains "$case_name" "$out" '^FAIL' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  tailscale-ssh-advertised' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  workspaces-dir' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  platform-contract' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_valid_host_bad_ssh() {
  local sandbox="$1" stub_path="$2"
  local case_name="valid-host-bad-ssh"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 755 "$dir/home/.ssh"
  : >"$dir/home/.ssh/id_rsa"
  chmod 600 "$dir/home/.ssh/id_rsa"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0 total_lines
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 1 "$rc" || ok=1
  assert_stdout_contains "$case_name" "$out" '^FAIL  ssh-dir-perms' || ok=1
  total_lines="$(grep -Ec '^(PASS|FAIL|SKIP)' "$out" || true)"
  if [ "${total_lines:-0}" -lt 5 ]; then
    printf 'self-test FAILED [%s]: expected multiple check lines, got %s\n' "$case_name" "${total_lines:-0}" >&2
    ok=1
  fi
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_valid_host_all_pass() {
  local sandbox="$1" stub_path="$2"
  local case_name="valid-host-all-pass"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  : >"$dir/home/.ssh/id_ed25519"
  chmod 600 "$dir/home/.ssh/id_ed25519"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_not_contains "$case_name" "$out" '^FAIL' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_role_from_env_var() {
  local sandbox="$1" stub_path="$2"
  local case_name="role-from-env-var"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    DOCTOR_STUB_TS_STATE=running \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  tailscale-ssh-advertised' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_role_from_flag() {
  local sandbox="$1" stub_path="$2"
  local case_name="role-from-flag"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" \
    DOCTOR_STUB_TS_STATE=running \
    bash "$SCRIPT_PATH" --role client >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  tailscale-ssh-advertised' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_macos_backend() {
  local sandbox="$1" stub_path="$2"
  local case_name="macos-backend"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0

  out="$dir/pass-out"
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Darwin DOCTOR_STUB_TAILSCALED_PATH=/opt/homebrew/bin/tailscaled \
    bash "$SCRIPT_PATH" >"$out" 2>"$dir/pass-err" || true
  assert_stdout_contains "$case_name-homebrew" "$out" '^PASS  platform-contract' || ok=1

  out="$dir/fail-out"
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Darwin DOCTOR_STUB_TAILSCALED_PATH=/Applications/Tailscale.app/Contents/MacOS/tailscaled \
    bash "$SCRIPT_PATH" >"$out" 2>"$dir/fail-err" || true
  assert_stdout_contains "$case_name-gui-app" "$out" '^FAIL  platform-contract' || ok=1

  return "$ok"
}

selftest_case_wsl_pid1() {
  local sandbox="$1" stub_path="$2"
  local case_name="wsl-pid1"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out ok=0

  out="$dir/pass-out"
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" WSL_DISTRO_NAME=test-distro \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_PID1=systemd \
    bash "$SCRIPT_PATH" >"$out" 2>"$dir/pass-err" || true
  assert_stdout_contains "$case_name-systemd" "$out" '^PASS  platform-contract' || ok=1

  out="$dir/fail-out"
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" WSL_DISTRO_NAME=test-distro \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_PID1=init \
    bash "$SCRIPT_PATH" >"$out" 2>"$dir/fail-err" || true
  assert_stdout_contains "$case_name-non-systemd" "$out" '^FAIL  platform-contract' || ok=1

  return "$ok"
}

run_other_scripts_check() {
  local script base self_base rc_all=0
  self_base="$(basename "$SCRIPT_PATH")"
  for script in "$SCRIPT_DIR"/*.sh; do
    [ -e "$script" ] || continue
    base="$(basename "$script")"
    [ "$base" = "$self_base" ] && continue
    if [ ! -x "$script" ]; then
      printf 'SKIP  other-script:%s -- not executable\n' "$base"
      continue
    fi
    if "$script" --check >/dev/null 2>&1; then
      printf 'PASS  other-script:%s\n' "$base"
    else
      printf 'FAIL  other-script:%s -- scripts/%s --check failed\n' "$base" "$base"
      rc_all=1
    fi
  done
  return "$rc_all"
}

run_self_test() {
  # Deliberately not `local`: the EXIT trap below must still see it after
  # this function returns (bash pops `local`s before the trap fires).
  SELFTEST_SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/doctor-selftest.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$SELFTEST_SANDBOX'" EXIT

  local bin_dir="$SELFTEST_SANDBOX/bin" stub_path overall_rc=0
  mkdir -p "$bin_dir"
  write_stub_tools "$bin_dir"
  stub_path="$bin_dir:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"

  selftest_case_missing_config "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_invalid_role "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_valid_client "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_valid_host_bad_ssh "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_valid_host_all_pass "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_role_from_env_var "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_role_from_flag "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_macos_backend "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_wsl_pid1 "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  run_other_scripts_check || overall_rc=1

  if [ "$overall_rc" -eq 0 ]; then
    printf 'PASS  self-test -- all doctor.sh --check assertions passed\n'
  else
    printf 'FAIL  self-test -- one or more --check assertions failed (see stderr)\n' >&2
  fi
  return "$overall_rc"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --check)
        RUN_CHECK=1
        shift
        ;;
      --role)
        if [ $# -lt 2 ]; then
          printf -- '--role requires an argument\n' >&2
          exit 2
        fi
        ROLE_FLAG="$2"
        shift 2
        ;;
      --role=*)
        ROLE_FLAG="${1#--role=}"
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        exit 2
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if [ "$RUN_CHECK" -eq 1 ]; then
    run_self_test
    exit $?
  fi

  resolve_and_validate_role
  run_common_checks
  run_host_checks

  if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

main "$@"
