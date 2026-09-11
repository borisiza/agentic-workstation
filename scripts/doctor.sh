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
  FALLBACK_SSHD="${FALLBACK_SSHD:-0}"
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
  if [ "$FALLBACK_SSHD" = "1" ]; then
    emit SKIP "tailscale-ssh-advertised" "FALLBACK_SSHD=1: this host uses the documented OpenSSH fallback instead"
    return
  fi
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
      if [ "$FALLBACK_SSHD" = "1" ]; then
        emit SKIP "platform-contract" "FALLBACK_SSHD=1: Homebrew tailscaled backend not required for the OpenSSH fallback"
      else
        check_macos_backend
      fi
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

# ---------------------------------------------------------------------------
# Fallback OpenSSH checks (host|both, only when FALLBACK_SSHD=1)
# ---------------------------------------------------------------------------

check_sshd_running() {
  if pgrep -x sshd >/dev/null 2>&1; then
    emit PASS "sshd-running" ""
  else
    emit FAIL "sshd-running" "start sshd: macOS -- enable Remote Login in System Settings > General > Sharing; Linux/WSL -- sudo systemctl enable --now ssh (or sshd)"
  fi
}

check_sshd_hardening() {
  local sshd_bin="" candidate
  # Real sbin paths by default; overridable so the self-test can exercise
  # the PATH-fallback branch hermetically without touching the real /usr/sbin.
  local -a sbin_candidates=(/usr/sbin/sshd /sbin/sshd)
  if [ -n "${DOCTOR_STUB_SSHD_SBIN_PATHS:-}" ]; then
    # shellcheck disable=SC2206 # intentional word-splitting of a test-only path list
    sbin_candidates=($DOCTOR_STUB_SSHD_SBIN_PATHS)
  fi
  if command -v sshd >/dev/null 2>&1; then
    sshd_bin="sshd"
  else
    for candidate in "${sbin_candidates[@]}"; do
      if [ -x "$candidate" ]; then
        sshd_bin="$candidate"
        break
      fi
    done
  fi
  if [ -z "$sshd_bin" ]; then
    emit FAIL "sshd-hardening" "sshd not found on PATH or in /usr/sbin, /sbin"
    return
  fi
  local out
  if ! out="$("$sshd_bin" -T 2>/dev/null)"; then
    emit FAIL "sshd-hardening" "sshd -T failed -- check sshd_config for syntax errors"
    return
  fi

  local bad="" setting actual
  for setting in passwordauthentication permitrootlogin; do
    actual="$(printf '%s\n' "$out" | awk -v s="$setting" 'tolower($1)==s {print tolower($2)}')"
    if [ "$actual" != "no" ]; then
      bad="$bad $setting=${actual:-unset}"
    fi
  done

  # KbdInteractiveAuthentication was ChallengeResponseAuthentication before OpenSSH 8.7.
  actual="$(printf '%s\n' "$out" | awk 'tolower($1)=="kbdinteractiveauthentication" {print tolower($2)}')"
  if [ -z "$actual" ]; then
    actual="$(printf '%s\n' "$out" | awk 'tolower($1)=="challengeresponseauthentication" {print tolower($2)}')"
  fi
  if [ "$actual" != "no" ]; then
    bad="$bad kbdinteractiveauthentication=${actual:-unset}"
  fi

  local allowusers_line
  allowusers_line="$(printf '%s\n' "$out" | awk 'tolower($1)=="allowusers" {for(i=2;i<=NF;i++) printf "%s ", tolower($i); print ""}')"
  allowusers_line="$(printf '%s' "$allowusers_line" | sed 's/[[:space:]]*$//')"
  if [ -z "$allowusers_line" ]; then
    bad="$bad allowusers=unset"
  elif [ "$(printf '%s' "$allowusers_line" | wc -w | tr -d ' ')" != "1" ]; then
    bad="$bad allowusers=multiple($allowusers_line)"
  else
    case "$allowusers_line" in
      *'*'* | *'?'*) bad="$bad allowusers=wildcard($allowusers_line)" ;;
    esac
  fi

  if [ -n "$bad" ]; then
    emit FAIL "sshd-hardening" "fix sshd_config:${bad}"
  else
    emit PASS "sshd-hardening" ""
  fi
}

check_authorized_keys_perms() {
  local ssh_dir="$HOME/.ssh" ak="$HOME/.ssh/authorized_keys"
  local dir_mode ak_mode bad=""

  if [ ! -d "$ssh_dir" ]; then
    emit FAIL "authorized-keys-perms" "create $ssh_dir and run: chmod 700 $ssh_dir"
    return
  fi
  dir_mode="$(octal_mode "$ssh_dir")"
  if [ "$dir_mode" != "700" ]; then
    bad="${bad}$ssh_dir is $dir_mode (want 700); "
  fi

  if [ ! -f "$ak" ]; then
    bad="${bad}create $ak with the allowed public key(s), then: chmod 600 $ak"
    emit FAIL "authorized-keys-perms" "$bad"
    return
  fi
  ak_mode="$(octal_mode "$ak")"
  if [ "$ak_mode" != "600" ]; then
    bad="${bad}$ak is $ak_mode (want 600)"
  fi

  if [ -n "$bad" ]; then
    emit FAIL "authorized-keys-perms" "$bad"
  else
    emit PASS "authorized-keys-perms" ""
  fi
}

run_host_checks() {
  case "$ROLE" in
    host | both)
      check_tailscale_ssh_advertised
      check_workspaces_dir
      check_platform_contract
      if [ "$FALLBACK_SSHD" = "1" ]; then
        check_sshd_running
        check_sshd_hardening
        check_authorized_keys_perms
      else
        emit SKIP "sshd-running" "FALLBACK_SSHD=${FALLBACK_SSHD} (not 1)"
        emit SKIP "sshd-hardening" "FALLBACK_SSHD=${FALLBACK_SSHD} (not 1)"
        emit SKIP "authorized-keys-perms" "FALLBACK_SSHD=${FALLBACK_SSHD} (not 1)"
      fi
      ;;
    client)
      emit SKIP "tailscale-ssh-advertised" "client role"
      emit SKIP "workspaces-dir" "client role"
      emit SKIP "platform-contract" "client role"
      emit SKIP "sshd-running" "client role"
      emit SKIP "sshd-hardening" "client role"
      emit SKIP "authorized-keys-perms" "client role"
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
case "$*" in
  *tailscaled*)
    if [ -n "${DOCTOR_STUB_TAILSCALED_PATH:-}" ]; then
      printf '4242 %s\n' "$DOCTOR_STUB_TAILSCALED_PATH"
      exit 0
    fi
    exit 1
    ;;
  *sshd*)
    if [ "${DOCTOR_STUB_SSHD_RUNNING:-0}" = "1" ]; then
      printf '4343\n'
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF

  cat >"$bin_dir/sshd" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -T)
    if [ "${DOCTOR_STUB_SSHD_T_FAILS:-0}" = "1" ]; then
      exit 1
    fi
    printf 'passwordauthentication %s\n' "${DOCTOR_STUB_SSHD_PASSWORDAUTHENTICATION:-no}"
    printf 'permitrootlogin %s\n' "${DOCTOR_STUB_SSHD_PERMITROOTLOGIN:-no}"
    if [ "${DOCTOR_STUB_SSHD_OMIT_KBDINTERACTIVE:-0}" = "1" ]; then
      # Pre-OpenSSH-8.7 sshd: no kbdinteractiveauthentication key at all,
      # only the older challengeresponseauthentication alias.
      printf 'challengeresponseauthentication %s\n' "${DOCTOR_STUB_SSHD_CHALLENGERESPONSEAUTHENTICATION:-no}"
    else
      printf 'kbdinteractiveauthentication %s\n' "${DOCTOR_STUB_SSHD_KBDINTERACTIVEAUTHENTICATION:-no}"
    fi
    if [ "${DOCTOR_STUB_SSHD_OMIT_ALLOWUSERS:-0}" != "1" ]; then
      printf 'allowusers %s\n' "${DOCTOR_STUB_SSHD_ALLOWUSERS:-testuser}"
    fi
    ;;
  *)
    exit 0
    ;;
esac
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
    "$bin_dir"/uname "$bin_dir"/pgrep "$bin_dir"/ps "$bin_dir"/sshd
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

selftest_case_fallback_sshd_disabled() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-sshd-disabled"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
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
  assert_stdout_contains "$case_name" "$out" '^PASS  tailscale-ssh-advertised' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  sshd-running' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  sshd-hardening' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  authorized-keys-perms' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_fallback_sshd_hardened() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-sshd-hardened"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  printf 'ssh-ed25519 AAAAtest test\n' >"$dir/home/.ssh/authorized_keys"
  chmod 600 "$dir/home/.ssh/authorized_keys"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_not_contains "$case_name" "$out" '^FAIL' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  tailscale-ssh-advertised' || ok=1
  assert_stdout_contains "$case_name" "$out" '^PASS  sshd-running' || ok=1
  assert_stdout_contains "$case_name" "$out" '^PASS  sshd-hardening' || ok=1
  assert_stdout_contains "$case_name" "$out" '^PASS  authorized-keys-perms' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_fallback_sshd_bad_hardening() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-sshd-bad-hardening"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  printf 'ssh-ed25519 AAAAtest test\n' >"$dir/home/.ssh/authorized_keys"
  chmod 600 "$dir/home/.ssh/authorized_keys"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    DOCTOR_STUB_SSHD_PERMITROOTLOGIN=yes \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 1 "$rc" || ok=1
  assert_stdout_contains "$case_name" "$out" '^FAIL  sshd-hardening.*permitrootlogin' || ok=1
  assert_stdout_contains "$case_name" "$out" '^PASS  sshd-running' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1

  # The shared loop also covers passwordauthentication -- exercise it too,
  # not just permitrootlogin, so a regression there wouldn't go unnoticed.
  out="$dir/pwauth-out"
  err="$dir/pwauth-err"
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    DOCTOR_STUB_SSHD_PASSWORDAUTHENTICATION=yes \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name-passwordauth" 1 "$rc" || ok=1
  assert_stdout_contains "$case_name-passwordauth" "$out" '^FAIL  sshd-hardening.*passwordauthentication' || ok=1
  assert_no_leak "$case_name-passwordauth" "$out" || ok=1
  return "$ok"
}

selftest_case_fallback_sshd_not_running() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-sshd-not-running"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  printf 'ssh-ed25519 AAAAtest test\n' >"$dir/home/.ssh/authorized_keys"
  chmod 600 "$dir/home/.ssh/authorized_keys"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 1 "$rc" || ok=1
  assert_stdout_contains "$case_name" "$out" '^FAIL  sshd-running' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_fallback_sshd_bad_key_perms() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-sshd-bad-key-perms"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  printf 'ssh-ed25519 AAAAtest test\n' >"$dir/home/.ssh/authorized_keys"
  chmod 644 "$dir/home/.ssh/authorized_keys"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 1 "$rc" || ok=1
  assert_stdout_contains "$case_name" "$out" '^FAIL  authorized-keys-perms' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_fallback_sshd_bad_dir_and_missing_keys() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-sshd-bad-dir-and-missing-keys"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  # ~/.ssh has the wrong mode AND authorized_keys is missing entirely: both
  # problems must be reported, not just the missing-file one.
  chmod 755 "$dir/home/.ssh"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 1 "$rc" || ok=1
  assert_stdout_contains "$case_name" "$out" '^FAIL  authorized-keys-perms.*\.ssh is 755' || ok=1
  assert_stdout_contains "$case_name" "$out" '^FAIL  authorized-keys-perms.*authorized_keys' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_fallback_sshd_client_role() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-sshd-client-role"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  printf 'NODE_ROLE=client\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_not_contains "$case_name" "$out" '^FAIL' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  tailscale-ssh-advertised' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  workspaces-dir' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  platform-contract' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  sshd-running' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  sshd-hardening' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  authorized-keys-perms' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_fallback_sshd_macos_gui_app() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-sshd-macos-gui-app"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  printf 'ssh-ed25519 AAAAtest test\n' >"$dir/home/.ssh/authorized_keys"
  chmod 600 "$dir/home/.ssh/authorized_keys"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Darwin DOCTOR_STUB_TAILSCALED_PATH=/Applications/Tailscale.app/Contents/MacOS/tailscaled \
    DOCTOR_STUB_SSHD_RUNNING=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  # The whole premise of this story is a Mac keeping the GUI app: the
  # Homebrew-tailscaled platform-contract requirement must not permanently
  # FAIL doctor.sh on that host once the OpenSSH fallback is opted into.
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_not_contains "$case_name" "$out" '^FAIL' || ok=1
  assert_stdout_contains "$case_name" "$out" '^SKIP  platform-contract' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_fallback_sshd_kbdinteractive_alias() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-sshd-kbdinteractive-alias"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  printf 'ssh-ed25519 AAAAtest test\n' >"$dir/home/.ssh/authorized_keys"
  chmod 600 "$dir/home/.ssh/authorized_keys"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out ok=0

  # Pre-OpenSSH-8.7 sshd (e.g. older Ubuntu/RHEL) reports
  # challengeresponseauthentication instead of kbdinteractiveauthentication;
  # "no" there must still PASS.
  out="$dir/pass-out"
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    DOCTOR_STUB_SSHD_OMIT_KBDINTERACTIVE=1 DOCTOR_STUB_SSHD_CHALLENGERESPONSEAUTHENTICATION=no \
    bash "$SCRIPT_PATH" >"$out" 2>"$dir/pass-err" || true
  assert_stdout_contains "$case_name-no" "$out" '^PASS  sshd-hardening' || ok=1

  # "yes" via the alias must still be caught as a hardening failure.
  out="$dir/fail-out"
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    DOCTOR_STUB_SSHD_OMIT_KBDINTERACTIVE=1 DOCTOR_STUB_SSHD_CHALLENGERESPONSEAUTHENTICATION=yes \
    bash "$SCRIPT_PATH" >"$out" 2>"$dir/fail-err" || true
  assert_stdout_contains "$case_name-yes" "$out" '^FAIL  sshd-hardening.*kbdinteractiveauthentication' || ok=1

  return "$ok"
}

selftest_case_fallback_sshd_allowusers_hardening() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-sshd-allowusers-hardening"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  printf 'ssh-ed25519 AAAAtest test\n' >"$dir/home/.ssh/authorized_keys"
  chmod 600 "$dir/home/.ssh/authorized_keys"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out ok=0

  out="$dir/wildcard-out"
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    DOCTOR_STUB_SSHD_ALLOWUSERS='*' \
    bash "$SCRIPT_PATH" >"$out" 2>"$dir/wildcard-err" || true
  assert_stdout_contains "$case_name-wildcard" "$out" '^FAIL  sshd-hardening.*allowusers' || ok=1

  out="$dir/multi-out"
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    DOCTOR_STUB_SSHD_ALLOWUSERS='alice bob' \
    bash "$SCRIPT_PATH" >"$out" 2>"$dir/multi-err" || true
  assert_stdout_contains "$case_name-multiple" "$out" '^FAIL  sshd-hardening.*allowusers' || ok=1

  # AllowUsers unset entirely (no line in `sshd -T` output at all) is the
  # most dangerous misconfiguration -- every local account can log in.
  out="$dir/unset-out"
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    DOCTOR_STUB_SSHD_OMIT_ALLOWUSERS=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$dir/unset-err" || true
  assert_stdout_contains "$case_name-unset" "$out" '^FAIL  sshd-hardening.*allowusers=unset' || ok=1

  return "$ok"
}

selftest_case_fallback_sshd_binary_not_on_path() {
  local sandbox="$1"
  local case_name="fallback-sshd-binary-not-on-path"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces" "$dir/no-sshd-bin" "$dir/sbin"
  chmod 700 "$dir/home/.ssh"
  printf 'ssh-ed25519 AAAAtest test\n' >"$dir/home/.ssh/authorized_keys"
  chmod 600 "$dir/home/.ssh/authorized_keys"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"

  # Build a PATH with every stub except sshd, so `command -v sshd` fails,
  # while a copy of the sshd stub lives at a stand-in sbin path that
  # check_sshd_hardening()'s fallback search should still find.
  local tool
  for tool in tailscale tmux claude git uname pgrep ps; do
    ln -s "$sandbox/bin/$tool" "$dir/no-sshd-bin/$tool"
  done
  cp "$sandbox/bin/sshd" "$dir/sbin/sshd"
  chmod +x "$dir/sbin/sshd"

  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$dir/no-sshd-bin:/usr/bin:/bin" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    DOCTOR_STUB_SSHD_SBIN_PATHS="$dir/sbin/sshd" \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_contains "$case_name" "$out" '^PASS  sshd-hardening' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_fallback_sshd_binary_not_found() {
  local sandbox="$1"
  local case_name="fallback-sshd-binary-not-found"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces" "$dir/no-sshd-bin"
  chmod 700 "$dir/home/.ssh"
  printf 'ssh-ed25519 AAAAtest test\n' >"$dir/home/.ssh/authorized_keys"
  chmod 600 "$dir/home/.ssh/authorized_keys"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"

  # No sshd on PATH, and the sbin fallback path doesn't exist either --
  # sshd_bin must stay empty and the check must FAIL with "not found",
  # not silently PASS or error out some other way.
  local tool
  for tool in tailscale tmux claude git uname pgrep ps; do
    ln -s "$sandbox/bin/$tool" "$dir/no-sshd-bin/$tool"
  done

  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$dir/no-sshd-bin:/usr/bin:/bin" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    DOCTOR_STUB_SSHD_SBIN_PATHS="$dir/nonexistent-sbin/sshd" \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 1 "$rc" || ok=1
  assert_stdout_contains "$case_name" "$out" '^FAIL  sshd-hardening.*not found' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
  return "$ok"
}

selftest_case_fallback_sshd_dash_t_fails() {
  local sandbox="$1" stub_path="$2"
  local case_name="fallback-sshd-dash-t-fails"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh" "$dir/workspaces"
  chmod 700 "$dir/home/.ssh"
  printf 'ssh-ed25519 AAAAtest test\n' >"$dir/home/.ssh/authorized_keys"
  chmod 600 "$dir/home/.ssh/authorized_keys"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" FALLBACK_SSHD=1 \
    DOCTOR_STUB_TS_STATE=running DOCTOR_STUB_TS_SSH=1 \
    DOCTOR_STUB_UNAME=Linux DOCTOR_STUB_SSHD_RUNNING=1 \
    DOCTOR_STUB_SSHD_T_FAILS=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 1 "$rc" || ok=1
  assert_stdout_contains "$case_name" "$out" '^FAIL  sshd-hardening.*sshd -T failed' || ok=1
  assert_no_leak "$case_name" "$out" || ok=1
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
  selftest_case_fallback_sshd_disabled "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_sshd_hardened "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_sshd_bad_hardening "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_sshd_not_running "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_sshd_bad_key_perms "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_sshd_bad_dir_and_missing_keys "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_sshd_client_role "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_sshd_macos_gui_app "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_sshd_kbdinteractive_alias "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_sshd_allowusers_hardening "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_fallback_sshd_binary_not_on_path "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_fallback_sshd_binary_not_found "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_fallback_sshd_dash_t_fails "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
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
