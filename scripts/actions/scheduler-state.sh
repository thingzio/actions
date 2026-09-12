#!/usr/bin/env bash
#
# Pauses or resumes a Cloud Scheduler job around a deployment.
#
#   scripts/actions/scheduler-state.sh pause
#   scripts/actions/scheduler-state.sh resume
#
#   SCHEDULER_JOB  Cloud Scheduler job name
#   REGION         its location
#
# Why this exists as its own script: the resume half runs under always(), so it
# executes after a failed deploy. It must therefore be the most boring code in
# the repository -- it cannot assume the pause succeeded, cannot assume the job
# is in the state it expected, and must not turn a deploy failure into a second,
# more confusing failure that masks the first.
#
# A paused scheduler is the failure mode worth engineering against. A failed
# deploy leaves the previous revision serving, which is visible and safe. A
# scheduler left paused stops scheduled work that nothing else is watching, and
# the symptom shows up hours later as "why did nothing run overnight".

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

GCLOUD_TIMEOUT="${GCLOUD_TIMEOUT:-60s}"

describe_state() {
  timeout "${GCLOUD_TIMEOUT}" gcloud scheduler jobs describe "${SCHEDULER_JOB}" \
    --location "${REGION}" --format='value(state)' 2>/dev/null || printf ''
}

do_pause() {
  local state
  state="$(describe_state)"
  case "${state}" in
    ENABLED)
      timeout "${GCLOUD_TIMEOUT}" gcloud scheduler jobs pause "${SCHEDULER_JOB}" --location "${REGION}"
      log "paused ${SCHEDULER_JOB}"
      ;;
    PAUSED)
      # Not an error, but worth saying: it means a previous run left it this
      # way, which is itself a thing to look at.
      warn "${SCHEDULER_JOB} was already paused before this deploy started"
      ;;
    '')
      die "could not read the state of ${SCHEDULER_JOB} in ${REGION}"
      ;;
    *)
      die "${SCHEDULER_JOB} is in an unexpected state: ${state}"
      ;;
  esac
}

# Resume is deliberately forgiving. It runs under always(), so it may be
# reached when the pause never happened, when authentication failed, or when
# the deploy died halfway. Resuming an already-enabled job is a no-op, and
# failing here would replace a useful error with a useless one.
do_resume() {
  local state
  state="$(describe_state)"
  case "${state}" in
    PAUSED)
      if timeout "${GCLOUD_TIMEOUT}" gcloud scheduler jobs resume "${SCHEDULER_JOB}" --location "${REGION}"; then
        log "resumed ${SCHEDULER_JOB}"
      else
        # Loud, because a scheduler left paused is an outage nobody is paged
        # for. The job still fails on the deploy error, if there was one.
        printf '::error::could not resume %s in %s -- RESUME IT BY HAND\n' \
          "${SCHEDULER_JOB}" "${REGION}" >&2
        return 1
      fi
      ;;
    ENABLED)
      log "${SCHEDULER_JOB} is already enabled"
      ;;
    '')
      warn "could not read the state of ${SCHEDULER_JOB}; not attempting to resume"
      ;;
    *)
      warn "${SCHEDULER_JOB} is in state ${state}; not attempting to resume"
      ;;
  esac
}

main() {
  require_set SCHEDULER_JOB "${SCHEDULER_JOB-}"
  require_set REGION "${REGION-}"
  case "${1-}" in
    pause) do_pause ;;
    resume) do_resume ;;
    *) die "usage: ${0##*/} <pause|resume>" ;;
  esac
}

main "$@"
