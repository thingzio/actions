#!/usr/bin/env bash
#
# Zero-dependency test runner for the shell in this repository.
#
#   test/run.sh              # every suite
#   test/run.sh derive-tags  # suites whose name contains "derive-tags"
#   test/run.sh '' rejects   # every suite, only tests matching "rejects"
#
# There is deliberately no test framework here. This repository's whole subject
# is supply-chain hygiene, and a framework we cannot checksum-pin (bats ships as
# a GitHub-generated source tarball with no stable checksum) would be a dependency
# we could not hold to our own standard. Sixty lines of bash is the cheaper
# honest answer.
#
# A test file is test/<name>_test.sh containing only function definitions. Any
# function named test_* is a test. It passes by returning zero. The runner
# sources the file once to discover tests, then runs each test in its own
# subshell so one test cannot leak state into the next.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

SUITE_FILTER="${1-}"
TEST_FILTER="${2-}"

PASS=0
FAIL=0
FAILURES=""

list_tests() {
  # Runs in a subshell: sourcing must not pollute the runner's own scope.
  (
    # shellcheck disable=SC1090
    . "$1" >/dev/null 2>&1
    declare -F | awk '{ print $3 }' | grep '^test_' | sort
  )
}

run_one() {
  local file="$1" name="$2" output status
  output="$(
    (
      set -uo pipefail
      # shellcheck disable=SC1091
      . "${REPO_ROOT}/test/lib/assert.sh"
      # shellcheck disable=SC1090
      . "${file}"
      "${name}"
    ) 2>&1
  )"
  status=$?

  if [ "${status}" = "0" ]; then
    PASS=$((PASS + 1))
    printf '  \033[32mok\033[0m   %s\n' "${name#test_}"
  else
    FAIL=$((FAIL + 1))
    FAILURES="${FAILURES}${file##*/}:${name}"$'\n'
    printf '  \033[31mFAIL\033[0m %s\n' "${name#test_}"
    printf '%s\n' "${output}" | sed 's/^/         /'
  fi
}

main() {
  local file suite name found=0

  for file in "${REPO_ROOT}"/test/*_test.sh; do
    [ -e "${file}" ] || continue
    suite="$(basename "${file}" _test.sh)"

    case "${suite}" in
      *"${SUITE_FILTER}"*) ;;
      *) continue ;;
    esac

    printf '\n%s\n' "${suite}"
    for name in $(list_tests "${file}"); do
      case "${name}" in
        *"${TEST_FILTER}"*) ;;
        *) continue ;;
      esac
      found=1
      run_one "${file}" "${name}"
    done
  done

  printf '\n'
  if [ "${found}" = "0" ]; then
    printf 'no tests matched (suite=%s test=%s)\n' "${SUITE_FILTER:-*}" "${TEST_FILTER:-*}" >&2
    return 1
  fi

  if [ "${FAIL}" -gt 0 ]; then
    printf '\033[31m%d failed\033[0m, %d passed\n\n' "${FAIL}" "${PASS}" >&2
    printf '%s' "${FAILURES}" | sed 's/^/  /' >&2
    return 1
  fi

  printf '\033[32m%d passed\033[0m\n' "${PASS}"
}

main "$@"
