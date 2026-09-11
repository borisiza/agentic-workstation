#!/usr/bin/env bash
# enroll.sh -- append a client's ed25519 public key to this host's
# ~/.ssh/authorized_keys, for the documented OpenSSH fallback
# (docs/fallback-openssh.md).
#
# Usage: enroll.sh <pubkey-file>
#        enroll.sh            (reads the pubkey from stdin)
#        enroll.sh --check
#        enroll.sh -h|--help
#
# Requires NODE_ROLE=host|both (config/local.env -> $NODE_ROLE, same
# precedence as doctor.sh/start-claude.sh) and FALLBACK_SSHD=1 -- otherwise
# exits 2 with one stderr line before touching anything. Input must be
# exactly one ed25519 public key line ("ssh-ed25519 <base64> [comment]"),
# taken from the file named by $1 or, with no argument, from stdin; any
# other key type, multiple keys, or unparsable input is the same exit-2
# refusal, with no side effects. The key is appended to
# ~/.ssh/authorized_keys only if an equivalent key (same algorithm +
# base64 material, ignoring the trailing comment) isn't already present.
# Every successful run fixes ~/.ssh to 0700 and authorized_keys to 0600,
# even when the key was already present. Never prints, logs, or echoes
# the key material. See config/local.env.example for the config file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]:-$0}")"
CONFIG_FILE="${DOCTOR_CONFIG_FILE:-$SCRIPT_DIR/../config/local.env}"

ROLE=""
KEY_TYPE=""
KEY_DATA=""
KEY_COMMENT=""

usage() {
  cat <<'EOF'
Usage: enroll.sh <pubkey-file>
       enroll.sh            (reads the pubkey from stdin)
       enroll.sh --check
       enroll.sh -h|--help

Appends one client's ed25519 public key to this host's
~/.ssh/authorized_keys, for the documented OpenSSH fallback (see
docs/fallback-openssh.md). Input must be exactly one
"ssh-ed25519 <base64> [comment]" line, from the file named by
<pubkey-file>, or from stdin if no argument is given. Any other key
type, multiple keys, or unparsable input is refused (exit 2, no side
effects). The key is appended only if an equivalent key (same
algorithm + base64 material, ignoring the comment) isn't already
present. Every successful run fixes ~/.ssh to 0700 and
authorized_keys to 0600. Never prints the key material.

Requires NODE_ROLE=host or NODE_ROLE=both, and FALLBACK_SSHD=1
(config/local.env or exported env vars).

  --check   run enroll.sh's own side-effect-free self-test and exit
  -h --help show this help
EOF
}

die2() {
  printf '%s\n' "$1" >&2
  exit 2
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

# Mirrors start-claude.sh's resolve_and_validate_role (host|both gate,
# same config/local.env -> $NODE_ROLE precedence), plus the FALLBACK_SSHD=1
# requirement unique to this fallback path.
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
      die2 "enroll.sh requires NODE_ROLE=host or NODE_ROLE=both (set it in config/local.env or export NODE_ROLE)."
      ;;
  esac

  if [ "${FALLBACK_SSHD:-0}" != "1" ]; then
    die2 "enroll.sh requires FALLBACK_SSHD=1 (set it in config/local.env or export FALLBACK_SSHD)."
  fi
}

# ---------------------------------------------------------------------------
# Pubkey validation
# ---------------------------------------------------------------------------

# validate_pubkey INPUT -- accepts exactly one "ssh-ed25519 <base64>
# [comment]" line, rejecting anything else (wrong key type, multiple
# keys/lines, garbage, a private key's multi-line body, ...). On success,
# sets the KEY_TYPE/KEY_DATA/KEY_COMMENT globals. Every real ssh-ed25519
# public key's base64 material is exactly 68 characters and starts with
# the fixed "AAAAC3NzaC1lZDI1NTE5AAAAI" prefix (it encodes the constant
# 4-byte-length-prefixed "ssh-ed25519" type string plus the start of the
# 32-byte key's own length prefix) -- checking that shape is a portable,
# tool-free way to validate the format without a base64 decoder, whose
# decode flag differs between GNU (`-d`) and BSD/macOS (`-D`) base64.
validate_pubkey() {
  local input="$1"
  local LC_ALL=C
  local nonblank_count=0 line="" candidate=""

  while IFS= read -r line || [ -n "$line" ]; do
    # Strip a trailing CR: $IFS word-splitting below doesn't include it, so
    # a CRLF-pasted key (common from Windows editors/chat clients) would
    # otherwise stick a stray \r onto the last field and fail validation
    # with a generic, non-diagnosable error.
    line="${line%$'\r'}"
    case "$line" in
      *[![:space:]]*)
        nonblank_count=$((nonblank_count + 1))
        candidate="$line"
        ;;
    esac
  done < <(printf '%s\n' "$input")

  if [ "$nonblank_count" -ne 1 ]; then
    die2 "enroll.sh requires exactly one ed25519 public key line as input (file arg or stdin)."
  fi

  local type="" keydata="" comment=""
  set -f
  # shellcheck disable=SC2086
  set -- $candidate
  set +f
  type="${1:-}"
  keydata="${2:-}"
  if [ $# -ge 2 ]; then
    shift 2
    comment="$*"
  fi

  if [ "$type" != "ssh-ed25519" ]; then
    die2 "enroll.sh only accepts a single ssh-ed25519 public key."
  fi

  case "$keydata" in
    AAAAC3NzaC1lZDI1NTE5AAAAI*) ;;
    *)
      die2 "enroll.sh only accepts a single ssh-ed25519 public key."
      ;;
  esac

  if [ "${#keydata}" -ne 68 ]; then
    die2 "enroll.sh only accepts a single ssh-ed25519 public key."
  fi

  case "$keydata" in
    *[![:alnum:]+/]*)
      die2 "enroll.sh only accepts a single ssh-ed25519 public key."
      ;;
  esac

  KEY_TYPE="$type"
  KEY_DATA="$keydata"
  KEY_COMMENT="$comment"
}

# ---------------------------------------------------------------------------
# Enroll
# ---------------------------------------------------------------------------

# enroll_key TYPE KEYDATA COMMENT -- ensures ~/.ssh (0700) and
# authorized_keys (0600) exist with the right permissions, then appends
# "TYPE KEYDATA [COMMENT]" unless an equivalent TYPE+KEYDATA line (ignoring
# comment) is already present. Never prints TYPE/KEYDATA/COMMENT.
enroll_key() {
  local type="$1" keydata="$2" comment="$3"
  local ssh_dir="$HOME/.ssh" ak="$HOME/.ssh/authorized_keys"

  mkdir -p "$ssh_dir" || die2 "Failed to create $ssh_dir."
  chmod 700 "$ssh_dir" || die2 "Failed to set $ssh_dir to mode 700."
  touch "$ak" || die2 "Failed to create $ak."
  chmod 600 "$ak" || die2 "Failed to set $ak to mode 600."

  local found=0 line="" existing_type="" existing_keydata=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '' | '#'*)
        continue
        ;;
    esac
    set -f
    # shellcheck disable=SC2086
    set -- $line
    set +f
    existing_type="${1:-}"
    existing_keydata="${2:-}"
    case "$existing_type" in
      ssh-*) ;;
      *)
        # The first token isn't a key type -- it's a leading key-restriction
        # options field (e.g. command="...",no-port-forwarding ssh-ed25519
        # <key> ...), a normal authorized_keys hardening pattern. The real
        # type/keydata are the *next* two tokens, not the first two;
        # otherwise this line would never match an existing restricted key
        # and enroll_key would append a second, unrestricted duplicate.
        existing_type="${2:-}"
        existing_keydata="${3:-}"
        ;;
    esac
    if [ "$existing_type" = "$type" ] && [ "$existing_keydata" = "$keydata" ]; then
      found=1
      break
    fi
  done <"$ak"

  if [ "$found" -eq 1 ]; then
    printf 'enroll.sh: key already present in %s\n' "$ak"
    return 0
  fi

  if [ -n "$comment" ]; then
    printf '%s %s %s\n' "$type" "$keydata" "$comment" >>"$ak"
  else
    printf '%s %s\n' "$type" "$keydata" >>"$ak"
  fi
  chmod 600 "$ak" || die2 "Failed to set $ak to mode 600."
  printf 'enroll.sh: key appended to %s\n' "$ak"
}

# ---------------------------------------------------------------------------
# --check self-test: fully sandboxed, deterministic, side-effect-free.
# ---------------------------------------------------------------------------

# Structurally valid (but not cryptographically meaningful) ed25519
# public keys: fixed 68-char base64 material starting with the fixed
# prefix every real ssh-ed25519 key shares (see validate_pubkey's
# comment). Good enough to exercise enroll.sh's own format check without
# shelling out to ssh-keygen just to build fixtures. Deliberately
# low-entropy (repeated characters, not random-looking) so these obvious
# fixtures never trip a secret scanner's generic-high-entropy-string rule.
TEST_KEY_A_DATA="AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
TEST_KEY_B_DATA="AAAAC3NzaC1lZDI1NTE5AAAAI1111111111111111111111111111111111111111111"

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

assert_mode_eq() {
  local case_name="$1" path="$2" expected="$3" actual
  actual="$(octal_mode "$path" 2>/dev/null || printf 'MISSING')"
  if [ "$actual" != "$expected" ]; then
    printf 'self-test FAILED [%s]: expected %s mode %s, got %s\n' "$case_name" "$path" "$expected" "$actual" >&2
    return 1
  fi
  return 0
}

assert_key_count_eq() {
  local case_name="$1" file="$2" keydata="$3" expected="$4" n
  n="$(grep -Fc -- "$keydata" "$file" 2>/dev/null || true)"
  n="${n:-0}"
  if [ "$n" -ne "$expected" ]; then
    printf 'self-test FAILED [%s]: expected %s occurrences of the key in %s, got %s\n' "$case_name" "$expected" "$file" "$n" >&2
    return 1
  fi
  return 0
}

assert_no_key_leak() {
  local case_name="$1" file="$2" keydata="$3"
  if [ -f "$file" ] && grep -Fq -- "$keydata" "$file"; then
    printf 'self-test FAILED [%s]: key material leaked into %s\n' "$case_name" "$file" >&2
    return 1
  fi
  return 0
}

selftest_case_first_enrollment_via_file() {
  local sandbox="$1"
  local case_name="first-enrollment-via-file"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  printf 'ssh-ed25519 %s alice@laptop\n' "$TEST_KEY_A_DATA" >"$dir/key.pub"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" "$dir/key.pub" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_file_contains "$case_name" "$ak" "ssh-ed25519 $TEST_KEY_A_DATA" || ok=1
  assert_mode_eq "$case_name" "$dir/home/.ssh" "700" || ok=1
  assert_mode_eq "$case_name" "$ak" "600" || ok=1
  assert_no_key_leak "$case_name-stdout" "$out" "$TEST_KEY_A_DATA" || ok=1
  assert_no_key_leak "$case_name-stderr" "$err" "$TEST_KEY_A_DATA" || ok=1
  return "$ok"
}

selftest_case_first_enrollment_via_stdin() {
  local sandbox="$1"
  local case_name="first-enrollment-via-stdin"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  printf 'ssh-ed25519 %s bob@desktop\n' "$TEST_KEY_A_DATA" | env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=both FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_file_contains "$case_name" "$ak" "ssh-ed25519 $TEST_KEY_A_DATA" || ok=1
  assert_mode_eq "$case_name" "$dir/home/.ssh" "700" || ok=1
  assert_mode_eq "$case_name" "$ak" "600" || ok=1
  assert_no_key_leak "$case_name-stdout" "$out" "$TEST_KEY_A_DATA" || ok=1
  assert_no_key_leak "$case_name-stderr" "$err" "$TEST_KEY_A_DATA" || ok=1
  return "$ok"
}

selftest_case_rerun_already_enrolled() {
  local sandbox="$1"
  local case_name="rerun-already-enrolled"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh"
  chmod 700 "$dir/home/.ssh"
  printf 'ssh-ed25519 %s old-comment\n' "$TEST_KEY_A_DATA" >"$dir/home/.ssh/authorized_keys"
  chmod 600 "$dir/home/.ssh/authorized_keys"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  printf 'ssh-ed25519 %s new-comment\n' "$TEST_KEY_A_DATA" | env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_key_count_eq "$case_name" "$ak" "$TEST_KEY_A_DATA" 1 || ok=1
  assert_mode_eq "$case_name" "$dir/home/.ssh" "700" || ok=1
  assert_mode_eq "$case_name" "$ak" "600" || ok=1
  assert_no_key_leak "$case_name-stdout" "$out" "$TEST_KEY_A_DATA" || ok=1
  assert_no_key_leak "$case_name-stderr" "$err" "$TEST_KEY_A_DATA" || ok=1
  return "$ok"
}

# Proves enroll_key() recognizes a leading key-restriction options field
# (a normal authorized_keys hardening pattern) so it doesn't misparse the
# type/keydata and append a second, unrestricted duplicate of an already-
# restricted key.
selftest_case_rerun_with_options_prefix() {
  local sandbox="$1"
  local case_name="rerun-with-options-prefix"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh"
  chmod 700 "$dir/home/.ssh"
  printf 'command="/usr/bin/true",no-port-forwarding ssh-ed25519 %s existing-user\n' \
    "$TEST_KEY_A_DATA" >"$dir/home/.ssh/authorized_keys"
  chmod 600 "$dir/home/.ssh/authorized_keys"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  printf 'ssh-ed25519 %s alice@laptop\n' "$TEST_KEY_A_DATA" | env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_key_count_eq "$case_name" "$ak" "$TEST_KEY_A_DATA" 1 || ok=1
  assert_file_contains "$case_name" "$ak" 'command="/usr/bin/true"' || ok=1
  return "$ok"
}

selftest_case_wrong_key_type() {
  local sandbox="$1"
  local case_name="wrong-key-type"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  printf 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDeadbeefdeadbeefdeadbeef alice@laptop\n' | \
    env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$ak" || ok=1
  return "$ok"
}

selftest_case_multiple_keys() {
  local sandbox="$1"
  local case_name="multiple-keys"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  {
    printf 'ssh-ed25519 %s alice@laptop\n' "$TEST_KEY_A_DATA"
    printf 'ssh-ed25519 %s bob@desktop\n' "$TEST_KEY_B_DATA"
  } >"$dir/keys.pub"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" "$dir/keys.pub" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$ak" || ok=1
  return "$ok"
}

selftest_case_garbage_input() {
  local sandbox="$1"
  local case_name="garbage-input"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  printf 'this is not a key\n' | env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$ak" || ok=1
  return "$ok"
}

selftest_case_multiline_garbage() {
  local sandbox="$1"
  local case_name="multiline-garbage"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  {
    printf 'this looks like it could be\n'
    printf 'a multi-line credential blob\n'
    printf 'but it is not a public key\n'
  } >"$dir/key"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" "$dir/key" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$ak" || ok=1
  return "$ok"
}

selftest_case_fallback_disabled() {
  local sandbox="$1"
  local case_name="fallback-disabled"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  printf 'ssh-ed25519 %s alice@laptop\n' "$TEST_KEY_A_DATA" | env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$ak" || ok=1
  assert_file_absent "$case_name-dir" "$dir/home/.ssh" || ok=1
  return "$ok"
}

selftest_case_client_role() {
  local sandbox="$1"
  local case_name="client-role"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  printf 'ssh-ed25519 %s alice@laptop\n' "$TEST_KEY_A_DATA" | env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=client FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$ak" || ok=1
  return "$ok"
}

selftest_case_broken_config() {
  local sandbox="$1"
  local case_name="broken-config"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  printf 'NODE_ROLE=host\nif [ \n' >"$dir/local.env"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  printf 'ssh-ed25519 %s alice@laptop\n' "$TEST_KEY_A_DATA" | env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/local.env" \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$ak" || ok=1
  return "$ok"
}

selftest_case_missing_file_arg() {
  local sandbox="$1"
  local case_name="missing-file-arg"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" "$dir/does-not-exist.pub" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$ak" || ok=1
  return "$ok"
}

selftest_case_too_many_args() {
  local sandbox="$1"
  local case_name="too-many-args"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  printf 'ssh-ed25519 %s alice@laptop\n' "$TEST_KEY_A_DATA" >"$dir/a.pub"
  printf 'ssh-ed25519 %s bob@desktop\n' "$TEST_KEY_B_DATA" >"$dir/b.pub"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" "$dir/a.pub" "$dir/b.pub" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 2 "$rc" || ok=1
  assert_stderr_one_line "$case_name" "$err" || ok=1
  assert_file_absent "$case_name" "$ak" || ok=1
  return "$ok"
}

selftest_case_perms_fixed_on_existing() {
  local sandbox="$1"
  local case_name="perms-fixed-on-existing"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home/.ssh"
  chmod 755 "$dir/home/.ssh"
  printf 'ssh-ed25519 %s existing-user\n' "$TEST_KEY_B_DATA" >"$dir/home/.ssh/authorized_keys"
  chmod 644 "$dir/home/.ssh/authorized_keys"
  local out="$dir/out" err="$dir/err" ak="$dir/home/.ssh/authorized_keys" rc=0 ok=0
  set +e
  printf 'ssh-ed25519 %s new-user\n' "$TEST_KEY_A_DATA" | env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    DOCTOR_CONFIG_FILE="$dir/absent-local.env" NODE_ROLE=host FALLBACK_SSHD=1 \
    "$SCRIPT_PATH" >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_mode_eq "$case_name" "$dir/home/.ssh" "700" || ok=1
  assert_mode_eq "$case_name" "$ak" "600" || ok=1
  assert_file_contains "$case_name" "$ak" "$TEST_KEY_A_DATA" || ok=1
  assert_file_contains "$case_name" "$ak" "$TEST_KEY_B_DATA" || ok=1
  return "$ok"
}

selftest_case_help() {
  local sandbox="$1"
  local case_name="help"
  local dir="$sandbox/$case_name"
  mkdir -p "$dir/home"
  local out="$dir/out" err="$dir/err" rc=0 ok=0
  set +e
  env -i PATH="/usr/bin:/bin" HOME="$dir/home" \
    "$SCRIPT_PATH" --help >"$out" 2>"$err"
  rc=$?
  set -e
  assert_exit_eq "$case_name" 0 "$rc" || ok=1
  assert_file_contains "$case_name" "$out" "Usage: enroll.sh" || ok=1
  return "$ok"
}

run_self_test() {
  # Deliberately not `local`: the EXIT trap below must still see it after
  # this function returns (bash pops `local`s before the trap fires).
  local tmpdir="${TMPDIR:-/tmp}"
  tmpdir="${tmpdir%/}"
  SELFTEST_SANDBOX="$(mktemp -d "$tmpdir/enroll-selftest.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$SELFTEST_SANDBOX'" EXIT

  local overall_rc=0

  selftest_case_first_enrollment_via_file "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_first_enrollment_via_stdin "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_rerun_already_enrolled "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_rerun_with_options_prefix "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_wrong_key_type "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_multiple_keys "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_garbage_input "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_multiline_garbage "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_fallback_disabled "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_client_role "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_broken_config "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_missing_file_arg "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_too_many_args "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_perms_fixed_on_existing "$SELFTEST_SANDBOX" || overall_rc=1
  selftest_case_help "$SELFTEST_SANDBOX" || overall_rc=1

  if [ "$overall_rc" -eq 0 ]; then
    printf 'PASS  self-test -- all enroll.sh --check assertions passed\n'
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

  local input=""
  case $# in
    0)
      input="$(cat)"
      ;;
    1)
      if [ ! -f "$1" ] || [ ! -r "$1" ]; then
        die2 "Cannot read pubkey file: $1"
      fi
      input="$(cat "$1")"
      ;;
    *)
      die2 "Usage: enroll.sh [<pubkey-file>] (see --help)"
      ;;
  esac

  validate_pubkey "$input"
  enroll_key "$KEY_TYPE" "$KEY_DATA" "$KEY_COMMENT"
}

main "$@"
