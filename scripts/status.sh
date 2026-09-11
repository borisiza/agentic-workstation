#!/usr/bin/env bash
# status.sh -- list claude-<workspace> tmux sessions running on this host.
#
# Usage: status.sh
#        status.sh --check
#        status.sh -h|--help
#
# Requires NODE_ROLE=host|both (config/local.env -> $NODE_ROLE, same
# precedence as doctor.sh/start-claude.sh). Lists every tmux session whose
# name matches claude-* from live tmux state only -- no state file is ever
# read or written. Prints one line per session as
# "<workspace> <attached|detached> <created>", or exactly "no sessions"
# (exit 0) when there are none or no tmux server is running. Never prints
# tokens, keys, tailnet IPs, or node names.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]:-$0}")"
CONFIG_FILE="${DOCTOR_CONFIG_FILE:-$SCRIPT_DIR/../config/local.env}"

ROLE=""

usage() {
  cat <<'EOF'
Usage: status.sh
       status.sh --check
       status.sh -h|--help

Lists every claude-<workspace> tmux session on this host, derived from
live tmux state only: one line per session as
"<workspace> <attached|detached> <created>", or "no sessions" when none
are running.

Requires NODE_ROLE=host or NODE_ROLE=both (config/local.env ->
$NODE_ROLE).

  --check   run status.sh's own side-effect-free self-test and exit
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
      die2 "status.sh requires NODE_ROLE=host or NODE_ROLE=both (set it in config/local.env or export NODE_ROLE)."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Listing
# ---------------------------------------------------------------------------

# list_raw_sessions -- prints raw "name|attached|created" lines from tmux,
# or nothing if no server is running / tmux list-sessions fails. Never
# fails itself so callers under `set -e` are unaffected.
list_raw_sessions() {
  local raw rc
  set +e
  raw="$(tmux list-sessions -F '#{session_name}|#{session_attached}|#{t:session_created}' 2>/dev/null)"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    return 0
  fi
  printf '%s\n' "$raw"
}

print_sessions() {
  local name attached created ws state found=0

  while IFS='|' read -r name attached created; do
    [ -n "$name" ] || continue
    case "$name" in
      claude-*)
        found=1
        ws="${name#claude-}"
        state="detached"
        if [ "$attached" -gt 0 ]; then
          state="attached"
        fi
        printf '%s %s %s\n' "$ws" "$state" "$created"
        ;;
    esac
  done < <(list_raw_sessions)

  if [ "$found" -eq 0 ]; then
    printf 'no sessions\n'
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
# real tmux server, and answers list-sessions from env-var-controlled
# canned output/exit code.
if [ -n "${STATUS_STUB_TMUX_ARGV_FILE:-}" ]; then
  printf '%s\n' "$@" >>"$STATUS_STUB_TMUX_ARGV_FILE"
fi
case "${1:-}" in
  list-sessions)
    if [ -n "${STATUS_STUB_TMUX_LIST_OUTPUT:-}" ]; then
      printf '%s\n' "$STATUS_STUB_TMUX_LIST_OUTPUT"
    fi
    exit "${STATUS_STUB_TMUX_LIST_EXIT:-0}"
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

assert_stdout_eq() {
  local case_name="$1" file="$2" expected="$3" actual
  actual="$(cat "$file" 2>/dev/null || true)"
  if [ "$actual" != "$expected" ]; then
    printf 'self-test FAILED [%s]: expected stdout %s, got %s\n' "$case_name" "$expected" "$actual" >&2
    return 1
  fi
  return 0
}

assert_stdout_contains() {
  local case_name="$1" file="$2" pattern="$3"
  if [ ! -f "$file" ] || ! grep -Fq -- "$pattern" "$file"; then
    printf 'self-test FAILED [%s]: expected %s to contain: %s\n' "$case_name" "$file" "$pattern" >&2
    return 1
  fi
  return 0
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
    STATUS_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
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
    STATUS_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
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
    STATUS_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
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
    STATUS_STUB_TMUX_ARGV_FILE="$argv" \
    STATUS_STUB_TMUX_LIST_EXIT=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_eq "$case_name" "$out" "no sessions" || ok=1
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
    STATUS_STUB_TMUX_ARGV_FILE="$argv" \
    STATUS_STUB_TMUX_LIST_EXIT=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_eq "$case_name" "$out" "no sessions" || ok=1
  return "$ok"
}

selftest_case_zero_sessions() {
  local sandbox="$1" stub_path="$2"
  local case_name="zero-sessions"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    STATUS_STUB_TMUX_ARGV_FILE="$argv" \
    STATUS_STUB_TMUX_LIST_EXIT=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_stdout_eq "$case_name" "$out" "no sessions" || ok=1
  return "$ok"
}

selftest_case_mixed_sessions() {
  local sandbox="$1" stub_path="$2"
  local case_name="mixed-sessions"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local list_output
  list_output="$(printf 'claude-demo|1|Fri Sep 11 12:00:00 2026\nclaude-idle|0|Fri Sep 11 11:00:00 2026\nother|0|Fri Sep 11 10:00:00 2026')"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    STATUS_STUB_TMUX_ARGV_FILE="$argv" \
    STATUS_STUB_TMUX_LIST_EXIT=0 \
    STATUS_STUB_TMUX_LIST_OUTPUT="$list_output" \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  # Exact full-stdout match (not substring): proves every field is present,
  # in the right order, on the right line -- a dropped/reordered/corrupted
  # `created` field (or a leaked `other` session) fails this, whereas a
  # substring check like `assert_stdout_contains "demo attached"` would not.
  local expected
  expected="$(printf 'demo attached Fri Sep 11 12:00:00 2026\nidle detached Fri Sep 11 11:00:00 2026')"
  assert_stdout_eq "$case_name" "$out" "$expected" || ok=1
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
  assert_stdout_contains "$case_name" "$out" "Usage: status.sh" || ok=1
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
    STATUS_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" unexpected-arg >"$out" 2>"$err"
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
  SELFTEST_SANDBOX="$(mktemp -d "$tmpdir/status-selftest.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$SELFTEST_SANDBOX'" EXIT

  local bin_dir="$SELFTEST_SANDBOX/bin" stub_path overall_rc=0
  mkdir -p "$bin_dir"
  write_stub_tools "$bin_dir"
  stub_path="$bin_dir:/usr/bin:/bin"

  selftest_case_wrong_role "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_missing_role "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_broken_config "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_role_from_config_overrides_env "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_role_both "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_zero_sessions "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_mixed_sessions "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_help "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_wrong_arg_count "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1

  if [ "$overall_rc" -eq 0 ]; then
    printf 'PASS  self-test -- all status.sh --check assertions passed\n'
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

  if [ $# -ne 0 ]; then
    die2 "Usage: status.sh (see --help)"
  fi

  resolve_and_validate_role
  print_sessions
}

main "$@"
