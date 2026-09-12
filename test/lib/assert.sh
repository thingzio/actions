# shellcheck shell=bash
#
# Assertions for the shell test harness. Sourced by test/run.sh before each test
# function; test files may assume every helper here is available.
#
# Every assertion prints a diagnostic to stderr and returns non-zero on failure.
# The harness treats any non-zero return from a test function as a failure, so
# tests read as a straight list of assertions with no boilerplate.

# assert_eq <expected> <actual> [message]
assert_eq() {
  if [ "$1" != "$2" ]; then
    printf 'assert_eq failed%s\n  expected: %s\n  actual:   %s\n' \
      "${3:+ -- $3}" "$1" "$2" >&2
    return 1
  fi
}

# assert_ne <unexpected> <actual> [message]
assert_ne() {
  if [ "$1" = "$2" ]; then
    printf 'assert_ne failed%s\n  both values were: %s\n' "${3:+ -- $3}" "$1" >&2
    return 1
  fi
}

# assert_contains <haystack> <needle> [message]
assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  printf 'assert_contains failed%s\n  needle:   %s\n  haystack: %s\n' \
    "${3:+ -- $3}" "$2" "$1" >&2
  return 1
}

# assert_not_contains <haystack> <needle> [message]
assert_not_contains() {
  case "$1" in
    *"$2"*)
      printf 'assert_not_contains failed%s\n  needle:   %s\n  haystack: %s\n' \
        "${3:+ -- $3}" "$2" "$1" >&2
      return 1
      ;;
  esac
  return 0
}

# run <command> [args...]
#
# Runs a command without letting its failure abort the test, capturing its
# streams and exit status into RUN_OUT, RUN_ERR and RUN_RC. This is the only
# correct way to test a script that calls die(), because die() exits.
run() {
  local outfile errfile
  outfile="$(mktemp)"
  errfile="$(mktemp)"
  "$@" >"${outfile}" 2>"${errfile}"
  RUN_RC=$?
  RUN_OUT="$(cat "${outfile}")"
  RUN_ERR="$(cat "${errfile}")"
  rm -f "${outfile}" "${errfile}"
  return 0
}

# assert_rc <expected-status> [message] -- asserts on the last run() call.
assert_rc() {
  if [ "${RUN_RC}" != "$1" ]; then
    printf 'assert_rc failed%s\n  expected status: %s\n  actual status:   %s\n  stdout: %s\n  stderr: %s\n' \
      "${2:+ -- $2}" "$1" "${RUN_RC}" "${RUN_OUT}" "${RUN_ERR}" >&2
    return 1
  fi
}

# assert_ok [message] -- the last run() call succeeded.
assert_ok() {
  if [ "${RUN_RC}" != "0" ]; then
    printf 'assert_ok failed%s\n  status: %s\n  stdout: %s\n  stderr: %s\n' \
      "${1:+ -- $1}" "${RUN_RC}" "${RUN_OUT}" "${RUN_ERR}" >&2
    return 1
  fi
}

# assert_failed [message] -- the last run() call exited non-zero.
assert_failed() {
  if [ "${RUN_RC}" = "0" ]; then
    printf 'assert_failed%s\n  expected a non-zero status but the command succeeded\n  stdout: %s\n' \
      "${1:+ -- $1}" "${RUN_OUT}" >&2
    return 1
  fi
}

# assert_stderr_contains <needle> [message] -- on the last run() call.
assert_stderr_contains() {
  assert_contains "${RUN_ERR}" "$1" "${2:-stderr}"
}

# assert_stdout_eq <expected> [message] -- on the last run() call.
assert_stdout_eq() {
  assert_eq "$1" "${RUN_OUT}" "${2:-stdout}"
}

# fixture_dir creates a per-test scratch directory that the harness removes.
fixture_dir() {
  mktemp -d "${TMPDIR:-/tmp}/thingz-test.XXXXXX"
}
