# shellcheck shell=bash
#
# Tests for scripts/actions/cloud-run-deploy.sh and
# scripts/actions/scheduler-state.sh.
#
# gcloud is stubbed. What is being tested is the decision-making these scripts
# do around it: that deploy order is honoured, that services and jobs use their
# own subcommand, and above all that resume behaves sanely when it runs after a
# failure -- which it always does, because it runs under always().

CLOUD_RUN_DEPLOY_SH="${REPO_ROOT}/scripts/actions/cloud-run-deploy.sh"
SCHEDULER_STATE_SH="${REPO_ROOT}/scripts/actions/scheduler-state.sh"

# _stub_gcloud writes a gcloud that logs its arguments and reports a scheduler
# state of $STATE, so a test can put the world in a given shape.
_stub_gcloud() {
  local dir="$1"
  mkdir -p "${dir}"
  cat >"${dir}/gcloud" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GCLOUD_LOG}"
case "$*" in
  *"scheduler jobs describe"*) printf '%s\n' "${STATE:-ENABLED}" ;;
  *"scheduler jobs resume"*)   [ "${RESUME_FAILS:-0}" = "1" ] && exit 1 ;;
esac
exit 0
STUB
  chmod +x "${dir}/gcloud"
  # timeout is not present on macOS; stub it as a pass-through.
  cat >"${dir}/timeout" <<'STUB'
#!/usr/bin/env bash
shift
exec "$@"
STUB
  chmod +x "${dir}/timeout"
}

_setup_stub() {
  WORK="$(mktemp -d)"
  _stub_gcloud "${WORK}/bin"
  GCLOUD_LOG="${WORK}/gcloud.log"
  : >"${GCLOUD_LOG}"
}

_run_deploy() {
  env -i PATH="${WORK}/bin:${PATH}" HOME="${HOME}" \
    GCLOUD_LOG="${GCLOUD_LOG}" REGION="us-west1" PLAN="$1" \
    bash "${CLOUD_RUN_DEPLOY_SH}" 2>&1
}

_run_scheduler() {
  local action="$1"
  shift
  env -i PATH="${WORK}/bin:${PATH}" HOME="${HOME}" \
    GCLOUD_LOG="${GCLOUD_LOG}" REGION="us-west1" SCHEDULER_JOB="deliver-scheduled" \
    "$@" \
    bash "${SCHEDULER_STATE_SH}" "${action}" 2>&1
}

test_services_and_jobs_use_their_own_subcommand() {
  _setup_stub
  _run_deploy "service my-serve us-west1-docker.pkg.dev/p/gh/o/i@sha256:abc
job my-job us-west1-docker.pkg.dev/p/gh/o/j@sha256:def" >/dev/null
  assert_contains "$(cat "${GCLOUD_LOG}")" 'run services update my-serve' \
    'a service must be updated with "run services update"'
  assert_contains "$(cat "${GCLOUD_LOG}")" 'run jobs update my-job' \
    'a job must be updated with "run jobs update"'
  rm -rf "${WORK}"
}

test_deploy_order_is_honoured() {
  # devradar updates its delivery consumer before its serve producer on
  # purpose. Reordering here would invert a deliberate sequence.
  _setup_stub
  _run_deploy "job deliver img@sha256:a
job scan img@sha256:b
service serve img@sha256:c" >/dev/null
  local order
  order="$(grep -oE 'update (deliver|scan|serve)' "${GCLOUD_LOG}" | tr '\n' ',')"
  assert_eq "update deliver,update scan,update serve," "${order}" \
    'targets must be deployed in the order the plan gives'
  rm -rf "${WORK}"
}

test_a_failed_target_stops_the_rollout() {
  _setup_stub
  cat >"${WORK}/bin/gcloud" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GCLOUD_LOG}"
case "$*" in *"update first"*) exit 1 ;; esac
exit 0
STUB
  chmod +x "${WORK}/bin/gcloud"
  local status
  _run_deploy "service first img@sha256:a
service second img@sha256:b" >/dev/null 2>&1 && status=0 || status=$?
  assert_ne 0 "${status}" 'a failed update must fail the step'
  assert_not_contains "$(cat "${GCLOUD_LOG}")" 'update second' \
    'the rollout must stop rather than continue past a failure'
  rm -rf "${WORK}"
}

test_pause_pauses_an_enabled_scheduler() {
  _setup_stub
  _run_scheduler pause STATE=ENABLED >/dev/null
  assert_contains "$(cat "${GCLOUD_LOG}")" 'scheduler jobs pause deliver-scheduled' \
    'an enabled scheduler must be paused'
  rm -rf "${WORK}"
}

test_pause_tolerates_an_already_paused_scheduler() {
  local out status
  _setup_stub
  out="$(_run_scheduler pause STATE=PAUSED)" && status=0 || status=$?
  assert_eq 0 "${status}" 'an already-paused scheduler is not a failure'
  assert_contains "${out}" 'already paused' 'but it is worth warning about'
  rm -rf "${WORK}"
}

test_pause_fails_on_an_unreadable_scheduler() {
  local status
  _setup_stub
  _run_scheduler pause STATE= >/dev/null 2>&1 && status=0 || status=$?
  assert_ne 0 "${status}" 'pausing must fail closed when the state cannot be read'
  rm -rf "${WORK}"
}

test_resume_resumes_a_paused_scheduler() {
  _setup_stub
  _run_scheduler resume STATE=PAUSED >/dev/null
  assert_contains "$(cat "${GCLOUD_LOG}")" 'scheduler jobs resume deliver-scheduled' \
    'a paused scheduler must be resumed'
  rm -rf "${WORK}"
}

test_resume_is_a_noop_when_already_enabled() {
  local status
  _setup_stub
  _run_scheduler resume STATE=ENABLED >/dev/null && status=0 || status=$?
  assert_eq 0 "${status}" 'resume runs under always(), so a no-op must succeed'
  assert_not_contains "$(cat "${GCLOUD_LOG}")" 'jobs resume' \
    'an enabled scheduler needs no resume call'
  rm -rf "${WORK}"
}

test_resume_does_not_fail_when_state_is_unreadable() {
  # This runs after a failed deploy, which may have failed at authentication.
  # Turning that into a second failure would mask the first.
  local out status
  _setup_stub
  out="$(_run_scheduler resume STATE=)" && status=0 || status=$?
  assert_eq 0 "${status}" 'an unreadable state must not mask the real deploy failure'
  assert_contains "${out}" 'not attempting to resume' 'but it must say so'
  rm -rf "${WORK}"
}

test_a_failed_resume_is_loud() {
  # The one case that must shout: the scheduler is paused, resuming failed, and
  # scheduled work is now silently stopped.
  local out status
  _setup_stub
  out="$(_run_scheduler resume STATE=PAUSED RESUME_FAILS=1)" && status=0 || status=$?
  assert_ne 0 "${status}" 'a scheduler left paused must fail the step'
  assert_contains "${out}" 'RESUME IT BY HAND' 'and must say exactly what to do'
  rm -rf "${WORK}"
}
