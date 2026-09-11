#!/usr/bin/env bash
# start-claude.sh -- start (or reattach to) a persistent tmux session
# running Claude Code for a workspace on this host.
#
# Usage: start-claude.sh <workspace>
#        start-claude.sh --check
#        start-claude.sh -h|--help
#
# Requires NODE_ROLE=host|both (config/local.env -> $NODE_ROLE, same
# precedence as doctor.sh) and must not run as root (EUID 0). <workspace>
# must match [a-z0-9-]+ and $WORKSPACES_DIR/<workspace> must already
# exist -- this script never creates workspaces. On success it execs:
#   tmux new -A -s claude-<workspace> -- bash -lc \
#     'cd "$WORKSPACES_DIR/<workspace>" && exec claude -n claude-<workspace> --permission-mode default'
# so re-running attaches to the existing session (idempotent) instead of
# starting a second Claude Code process. Never passes
# --dangerously-skip-permissions, bypassPermissions, or --add-dir. Never
# prints tokens, keys, tailnet IPs, or node names. See
# config/local.env.example for the config file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]:-$0}")"
CONFIG_FILE="${DOCTOR_CONFIG_FILE:-$SCRIPT_DIR/../config/local.env}"

ROLE=""

usage() {
  cat <<'EOF'
Usage: start-claude.sh <workspace>
       start-claude.sh --check
       start-claude.sh -h|--help

Starts, or reattaches to, a persistent tmux session named
claude-<workspace> running Claude Code with the workspace as its
current directory. Idempotent: re-running attaches to the existing
session (scrollback intact) instead of starting a second Claude Code
process.

Requires NODE_ROLE=host or NODE_ROLE=both (config/local.env ->
$NODE_ROLE) and must not run as root. <workspace> must match
[a-z0-9-]+ and $WORKSPACES_DIR/<workspace> must already exist --
this script never creates workspaces.

  --check   run start-claude.sh's own side-effect-free self-test and exit
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

check_not_root() {
  local euid="$EUID"
  if [ -n "${START_CLAUDE_STUB_EUID:-}" ] && [ -n "${START_CLAUDE_SELFTEST:-}" ]; then
    euid="$START_CLAUDE_STUB_EUID"
  fi
  if [ "$euid" -eq 0 ]; then
    die2 "start-claude.sh must not run as root (EUID 0)."
  fi
}

validate_workspace_name() {
  local ws="$1"
  local LC_ALL=C
  case "$ws" in
    "")
      die2 "Missing workspace name: usage: start-claude.sh <workspace>."
      ;;
    *[!a-z0-9-]*)
      die2 "Invalid workspace name '$ws': must match [a-z0-9-]+."
      ;;
  esac
}

# Mirrors doctor.sh's resolve_and_validate_role: config/local.env (if
# present) wins, then falls back to the inherited $NODE_ROLE env var.
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
      die2 "start-claude.sh requires NODE_ROLE=host or NODE_ROLE=both (set it in config/local.env or export NODE_ROLE)."
      ;;
  esac

  WORKSPACES_DIR="${WORKSPACES_DIR:-$HOME/workspaces}"
}

validate_workspace_dir() {
  local ws="$1" dir
  dir="$WORKSPACES_DIR/$ws"
  if [ ! -d "$dir" ]; then
    die2 "Workspace not found: $dir (create it first; start-claude.sh never creates workspaces)."
  fi
}

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

run_claude_session() {
  local ws="$1" session dir cmd dir_q session_q
  session="claude-$ws"
  dir="$WORKSPACES_DIR/$ws"
  dir_q="$(printf '%q' "$dir")"
  session_q="$(printf '%q' "$session")"
  cmd="cd $dir_q && exec claude -n $session_q --permission-mode default"
  exec tmux new -A -s "$session" -- bash -lc "$cmd"
}

# ---------------------------------------------------------------------------
# --check self-test: fully sandboxed, deterministic, side-effect-free.
# ---------------------------------------------------------------------------

write_stub_tools() {
  local bin_dir="$1"

  cat >"$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
# Records its argv (one element per line) instead of starting a real
# tmux server, so the self-test never attaches to a TTY.
if [ -n "${START_CLAUDE_STUB_TMUX_ARGV_FILE:-}" ]; then
  printf '%s\n' "$@" >"$START_CLAUDE_STUB_TMUX_ARGV_FILE"
fi
exit "${START_CLAUDE_STUB_TMUX_EXIT_CODE:-0}"
EOF

  cat >"$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude-stub pwd=%s args=%s\n' "$PWD" "$*"
exit 0
EOF

  chmod +x "$bin_dir/tmux" "$bin_dir/claude"
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

selftest_case_fresh_start() {
  local sandbox="$1" stub_path="$2"
  local case_name="fresh-start"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home" "$dir/workspaces/demo"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    START_CLAUDE_SELFTEST=1 \
    START_CLAUDE_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_file_contains "$case_name" "$argv" "new" || ok=1
  assert_file_contains "$case_name" "$argv" "-A" || ok=1
  assert_file_contains "$case_name" "$argv" "claude-demo" || ok=1
  assert_file_contains "$case_name" "$argv" "$dir/workspaces/demo" || ok=1
  assert_file_contains "$case_name" "$argv" "--permission-mode default" || ok=1
  assert_file_not_contains "$case_name" "$argv" "--dangerously-skip-permissions" || ok=1
  assert_file_not_contains "$case_name" "$argv" "bypassPermissions" || ok=1
  assert_file_not_contains "$case_name" "$argv" "--add-dir" || ok=1

  # Actually execute the constructed bash -lc command line (with the stub
  # claude on PATH) to verify it cds into the workspace and invokes claude
  # with the expected flags -- not just that the string looks right.
  local exec_line run_out
  exec_line="$(tail -n1 "$argv")"
  run_out="$dir/run-out"
  env -i PATH="$stub_path" HOME="$dir/home" bash -c "$exec_line" >"$run_out" 2>&1 || true
  assert_file_contains "$case_name-exec" "$run_out" "pwd=$dir/workspaces/demo" || ok=1
  assert_file_contains "$case_name-exec" "$run_out" "args=-n claude-demo --permission-mode default" || ok=1

  return "$ok"
}

selftest_case_role_from_config_overrides_env() {
  local sandbox="$1" stub_path="$2"
  local case_name="role-from-config-overrides-env"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home" "$dir/workspaces/demo"
  printf 'NODE_ROLE=host\n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" NODE_ROLE=client \
    START_CLAUDE_SELFTEST=1 \
    START_CLAUDE_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_file_contains "$case_name" "$argv" "claude-demo" || ok=1
  return "$ok"
}

selftest_case_bad_workspace_name() {
  local sandbox="$1" stub_path="$2"
  local case_name="bad-workspace-name"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home" "$dir/workspaces"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    START_CLAUDE_SELFTEST=1 \
    START_CLAUDE_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" "Bad Name!" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

selftest_case_missing_workspace_dir() {
  local sandbox="$1" stub_path="$2"
  local case_name="missing-workspace-dir"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home" "$dir/workspaces"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    START_CLAUDE_SELFTEST=1 \
    START_CLAUDE_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" ghost >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  if [ -d "$dir/workspaces/ghost" ]; then
    printf 'self-test FAILED [%s]: workspace directory was created\n' "$case_name" >&2
    ok=1
  fi
  return "$ok"
}

selftest_case_wrong_role() {
  local sandbox="$1" stub_path="$2"
  local case_name="wrong-role"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home" "$dir/workspaces/demo"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client \
    START_CLAUDE_SELFTEST=1 \
    START_CLAUDE_STUB_TMUX_ARGV_FILE="$argv" \
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
  mkdir -p "$dir/home" "$dir/workspaces/demo"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" \
    START_CLAUDE_SELFTEST=1 \
    START_CLAUDE_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

selftest_case_root() {
  local sandbox="$1" stub_path="$2"
  local case_name="root"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home" "$dir/workspaces/demo"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    START_CLAUDE_SELFTEST=1 \
    START_CLAUDE_STUB_EUID=0 \
    START_CLAUDE_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
  return "$ok"
}

selftest_case_role_both() {
  local sandbox="$1" stub_path="$2"
  local case_name="role-both"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home" "$dir/workspaces/demo"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=both \
    START_CLAUDE_SELFTEST=1 \
    START_CLAUDE_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_file_contains "$case_name" "$argv" "claude-demo" || ok=1
  return "$ok"
}

selftest_case_broken_config() {
  local sandbox="$1" stub_path="$2"
  local case_name="broken-config"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home" "$dir/workspaces/demo"
  printf 'NODE_ROLE=host\nif [ \n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" argv="$dir/tmux-argv" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" WORKSPACES_DIR="$dir/workspaces" \
    DOCTOR_CONFIG_FILE="$dir/local.env" \
    START_CLAUDE_SELFTEST=1 \
    START_CLAUDE_STUB_TMUX_ARGV_FILE="$argv" \
    bash "$SCRIPT_PATH" demo >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$argv" || ok=1
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
    START_CLAUDE_SELFTEST=1 \
    bash "$SCRIPT_PATH" --help >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_file_contains "$case_name" "$out" "Usage: start-claude.sh" || ok=1
  return "$ok"
}

selftest_case_wrong_arg_count() {
  local sandbox="$1" stub_path="$2"
  local case_name="wrong-arg-count"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="$stub_path" HOME="$dir/home" \
    START_CLAUDE_SELFTEST=1 \
    bash "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  return "$ok"
}

run_self_test() {
  # Deliberately not `local`: the EXIT trap below must still see it after
  # this function returns (bash pops `local`s before the trap fires).
  local tmpdir="${TMPDIR:-/tmp}"
  tmpdir="${tmpdir%/}"
  SELFTEST_SANDBOX="$(mktemp -d "$tmpdir/start-claude-selftest.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$SELFTEST_SANDBOX'" EXIT

  local bin_dir="$SELFTEST_SANDBOX/bin" stub_path overall_rc=0
  mkdir -p "$bin_dir"
  write_stub_tools "$bin_dir"
  stub_path="$bin_dir:/usr/bin:/bin"

  selftest_case_fresh_start "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_role_from_config_overrides_env "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_bad_workspace_name "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_missing_workspace_dir "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_wrong_role "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_missing_role "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_root "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_role_both "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_broken_config "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_help "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1
  selftest_case_wrong_arg_count "$SELFTEST_SANDBOX" "$stub_path" || overall_rc=1

  if [ "$overall_rc" -eq 0 ]; then
    printf 'PASS  self-test -- all start-claude.sh --check assertions passed\n'
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
    die2 "Usage: start-claude.sh <workspace> (see --help)"
  fi

  local workspace="$1"

  check_not_root
  validate_workspace_name "$workspace"
  resolve_and_validate_role
  validate_workspace_dir "$workspace"
  run_claude_session "$workspace"
}

main "$@"
