#!/usr/bin/env bash
#
# Points Cloud Run services and jobs at already-validated images.
#
#   PLAN    newline-separated "<kind> <name> <image>" lines, in deploy order
#   REGION  Cloud Run region
#
# Every value in PLAN has already been through deploy-targets.sh, which is the
# trust boundary. Nothing here re-parses caller input; it consumes a plan this
# repository produced.
#
# Order is honoured exactly as given, because it can carry meaning: devradar
# updates its delivery consumer before its serve producer so that a
# backward-compatible consumer is in place before the producer that feeds it.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

GCLOUD_TIMEOUT="${GCLOUD_TIMEOUT:-300s}"

deploy_one() {
  local kind="$1" name="$2" image="$3"
  case "${kind}" in
    service)
      log "deploying service ${name}"
      timeout "${GCLOUD_TIMEOUT}" gcloud run services update "${name}" \
        --region "${REGION}" --image "${image}"
      ;;
    job)
      log "deploying job ${name}"
      timeout "${GCLOUD_TIMEOUT}" gcloud run jobs update "${name}" \
        --region "${REGION}" --image "${image}"
      ;;
    *)
      die "unknown target kind '${kind}' in the plan"
      ;;
  esac
}

main() {
  local kind name image deployed=0 tick

  require_set REGION "${REGION-}"
  require_set plan "${PLAN-}"

  while read -r kind name image; do
    [ -n "${kind}" ] || continue
    deploy_one "${kind}" "${name}" "${image}"
    deployed=$((deployed + 1))
  done <<<"${PLAN}"

  log "deployed ${deployed} target(s)"

  # tick is a variable so shellcheck does not read the markdown backticks in
  # these format strings as command substitution (SC2016).
  tick='`'
  {
    printf '### Cloud Run deploy\n\n'
    printf '%s target(s) updated in %s%s%s:\n\n' "${deployed}" "${tick}" "${REGION}" "${tick}"
    while read -r kind name image; do
      [ -n "${kind}" ] || continue
      printf -- '- **%s** %s%s%s -> %s%s%s\n' \
        "${kind}" "${tick}" "${name}" "${tick}" "${tick}" "${image##*/}" "${tick}"
    done <<<"${PLAN}"
  } >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

main "$@"
