# shellcheck shell=bash
#
# Tests for scripts/actions/terraform-scan.sh.
#
# These exercise the input boundary, not Trivy. The scanner itself is proven by
# the selftest, which runs it against testdata/terraform for real; what matters
# here is that a bad severity fails loudly rather than silently changing what
# the gate covers. "HIGH,CRITCAL" passed through unchecked would scan for HIGH
# alone and report success, which is the quiet failure worth engineering
# against.

TERRAFORM_SCAN_SH="${REPO_ROOT}/scripts/actions/terraform-scan.sh"

# _fake_trivy writes a stub that records its arguments and emits an empty
# report, so the script can be exercised without the network or a real binary.
_fake_trivy() {
  local dir="$1"
  mkdir -p "${dir}"
  cat >"${dir}/trivy" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TRIVY_ARGS_LOG}"
out=""
prev=""
for a in "$@"; do
  if [ "${prev}" = "--output" ]; then out="${a}"; fi
  prev="${a}"
done
[ -n "${out}" ] && printf '{"Results":[]}' >"${out}"
exit 0
STUB
  chmod +x "${dir}/trivy"
}

_run_scan() {
  env -i \
    PATH="${PATH}" \
    HOME="${HOME}" \
    TRIVY_ARGS_LOG="${TRIVY_ARGS_LOG}" \
    "$@" \
    bash "${TERRAFORM_SCAN_SH}"
}

_setup() {
  WORK="$(mktemp -d)"
  mkdir -p "${WORK}/src/infra"
  _fake_trivy "${WORK}/bin"
  TRIVY_ARGS_LOG="${WORK}/args.log"
  : >"${TRIVY_ARGS_LOG}"
}

test_severity_is_normalized_to_upper_case() {
  local out
  _setup
  out="$(cd "${WORK}" && _run_scan \
    CHECKOUT_DIR=src WORKING_DIRECTORY=infra SEVERITY=high,critical \
    TRIVY_BIN="${WORK}/bin/trivy" 2>&1)"
  assert_contains "$(cat "${TRIVY_ARGS_LOG}")" 'HIGH,CRITICAL' \
    'a lower-case severity must reach trivy upper-cased'
  rm -rf "${WORK}"
}

test_severity_whitespace_is_trimmed() {
  _setup
  (cd "${WORK}" && _run_scan \
    CHECKOUT_DIR=src WORKING_DIRECTORY=infra SEVERITY='HIGH, CRITICAL' \
    TRIVY_BIN="${WORK}/bin/trivy" >/dev/null 2>&1)
  assert_contains "$(cat "${TRIVY_ARGS_LOG}")" 'HIGH,CRITICAL' \
    '"HIGH, CRITICAL" must not reach trivy with a space in it'
  rm -rf "${WORK}"
}

test_a_misspelled_severity_fails_loudly() {
  local out status
  _setup
  out="$(cd "${WORK}" && _run_scan \
    CHECKOUT_DIR=src WORKING_DIRECTORY=infra SEVERITY=HIGH,CRITCAL \
    TRIVY_BIN="${WORK}/bin/trivy" 2>&1)" && status=0 || status=$?
  assert_ne 0 "${status}" 'a misspelled severity must fail, not silently narrow the gate'
  assert_contains "${out}" 'CRITCAL' 'the error must name the offending value'
  rm -rf "${WORK}"
}

test_an_unknown_severity_is_rejected() {
  local status
  _setup
  (cd "${WORK}" && _run_scan \
    CHECKOUT_DIR=src WORKING_DIRECTORY=infra SEVERITY=SEVERE \
    TRIVY_BIN="${WORK}/bin/trivy" >/dev/null 2>&1) && status=0 || status=$?
  assert_ne 0 "${status}" 'a severity Trivy does not define must be rejected'
  rm -rf "${WORK}"
}

test_a_missing_directory_fails_before_scanning() {
  local out status
  _setup
  out="$(cd "${WORK}" && _run_scan \
    CHECKOUT_DIR=src WORKING_DIRECTORY=nope \
    TRIVY_BIN="${WORK}/bin/trivy" 2>&1)" && status=0 || status=$?
  assert_ne 0 "${status}" 'a working_directory that does not exist must fail'
  assert_eq "" "$(cat "${TRIVY_ARGS_LOG}")" 'trivy must not run when the target is missing'
  rm -rf "${WORK}"
}

test_exit_code_must_be_zero_or_one() {
  local status
  _setup
  (cd "${WORK}" && _run_scan \
    CHECKOUT_DIR=src WORKING_DIRECTORY=infra EXIT_CODE=7 \
    TRIVY_BIN="${WORK}/bin/trivy" >/dev/null 2>&1) && status=0 || status=$?
  assert_ne 0 "${status}" 'an exit_code outside {0,1} must be rejected'
  rm -rf "${WORK}"
}

test_the_scan_target_has_no_dot_segment() {
  # Same regression guard as the Go module cache: the caller's spelling of
  # "the repository root" must not survive into a composed path.
  local spelling
  for spelling in '.' './' ''; do
    _setup
    (cd "${WORK}" && _run_scan \
      CHECKOUT_DIR=src WORKING_DIRECTORY="${spelling}" \
      TRIVY_BIN="${WORK}/bin/trivy" >/dev/null 2>&1)
    assert_not_contains "$(cat "${TRIVY_ARGS_LOG}")" '/./' \
      "working_directory '${spelling}' produced a '.' path segment"
    assert_contains "$(cat "${TRIVY_ARGS_LOG}")" ' src ' \
      "working_directory '${spelling}' must scan the checkout root"
    rm -rf "${WORK}"
  done
}
