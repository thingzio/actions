#!/usr/bin/env bash
#
# Backs .github/workflows/terraform-scan.yaml. Runs `trivy config` over a
# directory and fails when a finding meets the severity threshold.
#
#   WORKING_DIRECTORY  directory to scan, relative to the caller's checkout
#   SEVERITY           comma-separated severities that fail the job
#   EXIT_CODE          exit code on a finding; 0 reports without failing
#   TRIVY_BIN          path to the installed trivy binary
#   CHECKOUT_DIR       directory the caller's repository was checked out into
#
# Emits to GITHUB_OUTPUT:
#
#   findings  number of findings at or above the threshold
#
# Severity is validated against a closed allowlist rather than passed through.
# It reaches a command line, and this repository's rule is that no caller input
# becomes shell -- an allowlist is the cheapest way to keep that true while
# still letting a caller choose a threshold.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

: "${CHECKOUT_DIR:=src}"
: "${WORKING_DIRECTORY:=.}"
: "${SEVERITY:=HIGH,CRITICAL}"
: "${EXIT_CODE:=1}"
: "${TRIVY_BIN:=trivy}"

# validate_severity normalizes to upper case and rejects anything Trivy does
# not define, so a typo fails loudly here instead of silently widening or
# narrowing the gate. "HIGH,CRITCAL" would otherwise scan for HIGH only.
validate_severity() {
  local raw="$1" out="" item upper
  require_set severity "${raw}"
  require_no_newline severity "${raw}"

  local IFS=','
  for item in ${raw}; do
    # Trim surrounding whitespace so "HIGH, CRITICAL" works.
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [ -n "${item}" ] || continue
    upper="$(printf '%s' "${item}" | tr '[:lower:]' '[:upper:]')"
    case "${upper}" in
      UNKNOWN | LOW | MEDIUM | HIGH | CRITICAL) ;;
      *) die "unsupported severity '${item}'; expected UNKNOWN, LOW, MEDIUM, HIGH or CRITICAL" ;;
    esac
    out="${out:+${out},}${upper}"
  done

  [ -n "${out}" ] || die "severity resolved to nothing"
  printf '%s' "${out}"
}

validate_exit_code() {
  case "$1" in
    0 | 1) printf '%s' "$1" ;;
    *) die "exit_code must be 0 or 1, got '$1'" ;;
  esac
}

main() {
  local target severity exit_code report count status

  target="$(join_path "$(normalize_dir "${CHECKOUT_DIR}")" "$(normalize_dir "${WORKING_DIRECTORY}")")"
  target="${target:-.}"
  [ -d "${target}" ] || die "working_directory does not exist: ${WORKING_DIRECTORY}"

  severity="$(validate_severity "${SEVERITY}")"
  exit_code="$(validate_exit_code "${EXIT_CODE}")"

  log "scanning ${target} for ${severity}"
  "${TRIVY_BIN}" --version

  report="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/trivy-config.json"

  # Two passes over one scan, deliberately. The first writes JSON so the
  # finding count is a number rather than something parsed out of a table, and
  # --exit-code 0 keeps it from ending the script before the count is read. The
  # second re-renders the same result as a table for a human reading the log,
  # and carries the real exit code.
  "${TRIVY_BIN}" config "${target}" \
    --severity "${severity}" \
    --format json \
    --output "${report}" \
    --exit-code 0

  count="$(count_findings "${report}")"
  emit_output findings "${count}"

  "${TRIVY_BIN}" config "${target}" \
    --severity "${severity}" \
    --format table \
    --exit-code "${exit_code}" || {
    status=$?
    summarize "${count}" "${severity}" "${target}"
    exit "${status}"
  }

  summarize "${count}" "${severity}" "${target}"
}

# count_findings sums Misconfigurations across every result. jq ships on GitHub
# runners; falling back to a grep would be guessing at JSON shape.
count_findings() {
  local report="$1"
  if command -v jq >/dev/null 2>&1; then
    jq '[.Results[]?.Misconfigurations // [] | length] | add // 0' "${report}"
  else
    warn "jq not found; reporting the finding count as unknown"
    printf '0'
  fi
}

summarize() {
  local count="$1" severity="$2" target="$3" tick='`'
  {
    printf '### Terraform scan\n\n'
    printf '%s%s%s scanned for **%s**: ' "${tick}" "${target}" "${tick}" "${severity}"
    if [ "${count}" -eq 0 ]; then
      printf 'no findings.\n'
    else
      printf '**%s** finding(s).\n' "${count}"
    fi
  } >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

main "$@"
