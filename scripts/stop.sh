#!/usr/bin/env bash
# stop.sh -- kill exactly one claude-<workspace> tmux session on this host.
#
# Usage: stop.sh <workspace>
#        stop.sh --check
#        stop.sh -h|--help
#
# Requires NODE_ROLE=host|both (config/local.env -> $NODE_ROLE, same
# precedence as doctor.sh/start-claude.sh). <workspace> must match
# [a-z0-9-]+. Kills exactly the named session with
# `tmux kill-session -t =claude-<workspace>` (the "=" sigil forces tmux's
# exact-match target resolution instead of its default unambiguous-prefix
# matching, which would otherwise let claude-<workspace> match an unrelated
# session like claude-<workspace>2) -- never a wildcard, never
# `tmux kill-server`. Other claude-* sessions are left untouched. Exits 2
# with one stderr line if no session named claude-<workspace> exists, or if
# the kill itself fails. Never prints tokens, keys, tailnet IPs, or node
# names.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]:-$0}")"
CONFIG_FILE="${DOCTOR_CONFIG_FILE:-$SCRIPT_DIR/../config/local.env}"

ROLE=""

usage() {
  cat <<'EOF'
Usage: stop.sh <workspace>
       stop.sh --check
       stop.sh -h|--help

Kills the tmux session claude-<workspace> -- exactly that one session,
never a wildcard and never tmux kill-server. Other claude-* sessions are
left untouched.

Requires NODE_ROLE=host or NODE_ROLE=both (config/local.env ->
$NODE_ROLE). <workspace> must match [a-z0-9-]+ and a session named
claude-<workspace> must already be running.

  --check   run stop.sh's own side-effect-free self-test and exit
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

# Reused verbatim from start-claude.sh.
validate_workspace_name() {
  local ws="$1"
  local LC_ALL=C
  case "$ws" in
    "")
      die2 "Missing workspace name: usage: stop.sh <workspace>."
      ;;
    *[!a-z0-9-]*)
      die2 "Invalid workspace name '$ws': must match [a-z0-9-]+."
      ;;
  esac
}

# Mirrors start-claude.sh's resolve_and_validate_role: config/local.env (if
# present) wins, then falls back to the inherited $NODE_ROLE env var. This
# story needs no $WORKSPACES_DIR.
resolve_and_validate_role() {
  if [ -f "$CONFIG_FILE" ]; then
    local source_rc=0
    set +eu
    # shellcheck source=/dev/null
    . "$CONFIG_FILE" 2>/dev/null
    source_rc=$?
    set -eu
    if [ "$source_rc" -ne 0 ]; then
      die2 "config/local.env failed to load: fix its syntax or restore it from config/local.env.example."
    fi
  fi

  ROLE="${NODE_ROLE:-}"
  case "$ROLE" in
    host | both)
      ;;
    *)
      die2 "stop.sh requires NODE_ROLE=host or NODE_ROLE=both (set it in config/local.env or export NODE_ROLE)."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Stop
# ---------------------------------------------------------------------------

stop_session() {
  local ws="$1" session
  session="claude-$ws"
  # The leading "=" forces tmux's exact-match resolution: without it, a
  # bare -t target can resolve via tmux's unambiguous-prefix matching (see
  # tmux(1) TARGET SPECIFICATION) and hit an unrelated session whose name
  # happens to start with claude-<ws> (e.g. claude-demo2), violating
  # AD-4's "never affects other sessions" invariant.
  if ! tmux has-session -t "=$session" 2>/dev/null; then
    die2 "No session named $session."
  fi
  if ! tmux kill-session -t "=$session" 2>/dev/null; then
    die2 "Failed to stop session $session."
  fi
}

# ---------------------------------------------------------------------------
# --check self-test: fully sandboxed, deterministic, side-effect-free.
# ---------------------------------------------------------------------------

write_stub_tools() {
  local bin_dir="$1"

  cat >"$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
# Records its argv (one element per line, appended) instead of starting a
# real tmux server, and answers has-session/kill-session from
# env-var-controlled exit codes.
if [ -n "${STOP_STUB_TMUX_ARGV_FILE:-}" ]; then
  printf '%s\n' "$@" >>"$STOP_STUB_TMUX_ARGV_FILE"
fi
case "${1:-}" in
  has-session)
    exit "${STOP_STUB_TMUX_HAS_EXIT:-0}"
    ;;
  kill-session)
    exit "${STOP_STUB_TMUX_KILL_EXIT:-0}"
    ;;
  *)
    exit 0
    ;;
esac
EOF

  chmod +x "$bin_dir/tmux"
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
    printf 'self-test FAILED [%s]: expected %s to not exist (tmux must not run)\n' "$case_name" "$file" >&2
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

assert_file_not_contains() {
  local case_name="$1" file="$2" pattern="$3"
  if [ -f "$file" ] && grep -Fq -- "$pattern" "$file"; then
    printf 'self-test FAILED [%s]: %s unexpectedly contained: %s\n' "$case_name" "$file" "$pattern" >&2
    return 1
  fi
  return 0
}

# assert_kill_session_argv_exact -- verifies the ENTIRE argv file is exactly
# the has-session call followed by the kill-session call, each targeting
# "=claude-<ws>" (the "=" exact-match sigil -- without it tmux's
# unambiguous-prefix matching could resolve to an unrelated session, e.g.
# claude-demo2; see tmux(1) TARGET SPECIFICATION). Checking the whole file
# (not just the last 3 lines) also proves no wildcard, no extra flags, and
# no kill-server call (AD-4).
assert_kill_session_argv_exact() {
  local case_name="$1" file="$2" ws="$3" expected actual
  expected="$(printf 'has-session\n-t\n=claude-%s\nkill-session\n-t\n=claude-%s' "$ws" "$ws")"
  actual="$(cat "$file" 2>/dev/null || true)"
  if [ "$actual" != "$expected" ]; then
    printf 'self-test FAILED [%s]: expected tmux argv sequence:\n%s\ngot:\n%s\n' "$case_name" "$expected" "$actual" >&2
    return 1
  fi
  return 0
}

selftest_case_running() {
  local sandbox="$1" stub_path="$2"
  local case_name="running"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    STOP_STUB_TMUX_ARGV_FILE="$argv" \
    STOP_STUB_TMUX_HAS_EXIT=0 STOP_STUB_TMUX_KILL_EXIT=0 \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_kill_session_argv_exact "$case_name" "$argv" "demo" || ok=1
  return "$ok"
}

selftest_case_kill_fails() {
  local sandbox="$1" stub_path="$2"
  local case_name="kill-fails"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    STOP_STUB_TMUX_ARGV_FILE="$argv" \
    STOP_STUB_TMUX_HAS_EXIT=0 STOP_STUB_TMUX_KILL_EXIT=1 \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_contains "$case_name" "$argv" "kill-session" || ok=1
  return "$ok"
}

selftest_case_absent() {
  local sandbox="$1" stub_path="$2"
  local case_name="absent"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    STOP_STUB_TMUX_ARGV_FILE="$argv" \
    STOP_STUB_TMUX_HAS_EXIT=1 \
    bash "$SCRIPT_PATH" ghost >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_contains "$case_name" "$argv" "has-session" || ok=1
  assert_file_not_contains "$case_name" "$argv" "kill-session" || ok=1
  return "$ok"
}

selftest_case_bad_workspace_name() {
  local sandbox="$1" stub_path="$2"
  local case_name="bad-workspace-name"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    STOP_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" "Bad Name!" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

selftest_case_wrong_role() {
  local sandbox="$1" stub_path="$2"
  local case_name="wrong-role"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    STOP_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

selftest_case_missing_role() {
  local sandbox="$1" stub_path="$2"
  local case_name="missing-role"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" \
    STOP_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

selftest_case_broken_config() {
  local sandbox="$1" stub_path="$2"
  local case_name="broken-config"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  printf 'NODE_ROLE=host\nif [ \n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/local.env" \
    STOP_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

selftest_case_role_from_config_overrides_env() {
  local sandbox="$1" stub_path="$2"
  local case_name="role-from-config-overrides-env"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/local.env" NODE_ROLE=client \
    STOP_STUB_TMUX_ARGV_FILE="$argv" \
    STOP_STUB_TMUX_HAS_EXIT=0 STOP_STUB_TMUX_KILL_EXIT=0 \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_kill_session_argv_exact "$case_name" "$argv" "demo" || ok=1
  return "$ok"
}

selftest_case_role_both() {
  local sandbox="$1" stub_path="$2"
  local case_name="role-both"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=both \
    STOP_STUB_TMUX_ARGV_FILE="$argv" \
    STOP_STUB_TMUX_HAS_EXIT=0 STOP_STUB_TMUX_KILL_EXIT=0 \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_kill_session_argv_exact "$case_name" "$argv" "demo" || ok=1
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
    bash "$SCRIPT_PATH" --help >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_file_contains "$case_name" "$out" "Usage: stop.sh" || ok=1
  return "$ok"
}

selftest_case_wrong_arg_count() {
  local sandbox="$1" stub_path="$2"
  local case_name="wrong-arg-count"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    STOP_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

run_self_test() {
  # Deliberately not `local`: the EXIT trap below must still see it after
  # this function returns (bash pops `local`s before the trap fires).
  local tmpdir="${TMPDIR:-/tmp}"
  tmpdir="${tmpdir%/}"
  SELFTEST_SANDBOX="$(mktemp -d "$tmpdir/stop-selftest.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$SELFTEST_SANDBOX'" EXIT

  local bin_dir="$SELFTEST_SANDBOX/bin" stub_path overall_rc=0
  mkdir -p "$bin_dir"
  write_stub_tools "$bin_dir"
  stub_path="$bin_dir:/usr/bin:/bin"

  selftest_case_running "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_kill_fails "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_absent "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_bad_workspace_name "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_wrong_role "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_missing_role "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_broken_config "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_role_from_config_overrides_env "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_role_both "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_help "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_wrong_arg_count "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1

  if [ "$overall_rc" -eq 0 ]; then
    printf 'PASS  self-test -- all stop.sh --check assertions passed\n'
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

  if [ $# -ne 1 ]; then
    die2 "Usage: stop.sh <workspace> (see --help)"
  fi

  local workspace="$1"

  validate_workspace_name "$workspace"
  resolve_and_validate_role
  stop_session "$workspace"
}

main "$@"
