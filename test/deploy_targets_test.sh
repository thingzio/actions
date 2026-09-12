# shellcheck shell=bash
#
# Tests for scripts/actions/deploy-targets.sh.
#
# This script decides what a production deploy points at, and every value it
# emits reaches a gcloud command line. The cases below are therefore weighted
# towards what must be REFUSED rather than what must work: a tag that could move
# between build and deploy, a digest that is not a digest, a resource name that
# could introduce a flag, and an image from a registry nobody published to.

DEPLOY_TARGETS_SH="${REPO_ROOT}/scripts/actions/deploy-targets.sh"

DIGEST="sha256:$(printf 'a%.0s' $(seq 1 64))"

_run_targets() {
  local targets="$1"
  shift
  env -i \
    PATH="${PATH}" \
    HOME="${HOME}" \
    REGION="us-west1" \
    PROJECT_ID="thingzio" \
    TARGETS="${targets}" \
    "$@" \
    bash "${DEPLOY_TARGETS_SH}" 2>&1
}

test_rewrites_a_service_onto_the_remote_repository() {
  local out
  out="$(_run_targets "service=devpulse-saas-serve=ghcr.io/thingzio/devpulse-site@${DIGEST}")"
  assert_contains "${out}" "us-west1-docker.pkg.dev/thingzio/gh/thingzio/devpulse-site@${DIGEST}" \
    'the image must be rewritten onto the remote repository, org segment intact'
  assert_contains "${out}" 'count=1' 'one target was given'
}

test_preserves_target_order() {
  # devradar updates the delivery consumer before the serve producer on
  # purpose. If this script reordered targets it would invert a deliberate
  # deployment sequence, so order is part of the contract.
  #
  # Asserted against a real GITHUB_OUTPUT file rather than stdout: the script
  # also logs the plan for humans, and the contract is what it emits.
  local outfile plan
  outfile="$(mktemp)"
  _run_targets "job=devradar-saas-deliver=ghcr.io/thingzio/devradar-deliver@${DIGEST}
job=devradar-saas-scan=ghcr.io/thingzio/devradar-scan@${DIGEST}
service=devradar-saas-serve=ghcr.io/thingzio/devradar-serve@${DIGEST}" \
    GITHUB_OUTPUT="${outfile}" >/dev/null
  plan="$(grep -oE '^(job|service) devradar-saas-[a-z]+' "${outfile}" | tr '\n' ',')"
  assert_eq "job devradar-saas-deliver,job devradar-saas-scan,service devradar-saas-serve," \
    "${plan}" 'targets must be emitted in the order they were given'
  rm -f "${outfile}"
}

test_rejects_a_tag() {
  local out status
  out="$(_run_targets "service=devpulse-saas-serve=ghcr.io/thingzio/devpulse-site:v1.2.3")" && status=0 || status=$?
  assert_ne 0 "${status}" 'a tag must never be accepted -- it can move between build and deploy'
  assert_contains "${out}" 'sha256' 'the error should say what was expected'
}

test_rejects_a_short_digest() {
  local status
  _run_targets "service=devpulse-saas-serve=ghcr.io/thingzio/devpulse-site@sha256:abc123" >/dev/null 2>&1 && status=0 || status=$?
  assert_ne 0 "${status}" 'a truncated digest must be rejected'
}

test_rejects_an_uppercase_digest() {
  local status
  _run_targets "service=x-serve=ghcr.io/thingzio/img@sha256:$(printf 'A%.0s' $(seq 1 64))" >/dev/null 2>&1 && status=0 || status=$?
  assert_ne 0 "${status}" 'a digest must be lowercase hex'
}

test_rejects_an_unexpected_registry() {
  local out status
  out="$(_run_targets "service=devpulse-saas-serve=docker.io/thingzio/devpulse-site@${DIGEST}")" && status=0 || status=$?
  assert_ne 0 "${status}" 'an image from another registry must be refused'
  assert_contains "${out}" 'ghcr.io' 'the error should name the expected registry'
}

test_rejects_a_name_that_could_introduce_a_flag() {
  local status
  _run_targets "service=--project=evil=ghcr.io/thingzio/img@${DIGEST}" >/dev/null 2>&1 && status=0 || status=$?
  assert_ne 0 "${status}" 'a resource name starting with a dash must be refused'
}

test_rejects_a_name_with_a_shell_metacharacter() {
  local status
  _run_targets "service=serve;rm -rf /=ghcr.io/thingzio/img@${DIGEST}" >/dev/null 2>&1 && status=0 || status=$?
  assert_ne 0 "${status}" 'a resource name with a metacharacter must be refused'
}

test_rejects_an_unknown_kind() {
  local status
  _run_targets "function=my-fn=ghcr.io/thingzio/img@${DIGEST}" >/dev/null 2>&1 && status=0 || status=$?
  assert_ne 0 "${status}" "only 'service' and 'job' are deployable here"
}

test_rejects_a_malformed_line() {
  local status
  _run_targets "service=devpulse-saas-serve" >/dev/null 2>&1 && status=0 || status=$?
  assert_ne 0 "${status}" 'a line missing its image must be refused'
}

test_rejects_an_empty_target_list() {
  local status
  _run_targets "" >/dev/null 2>&1 && status=0 || status=$?
  assert_ne 0 "${status}" 'deploying nothing is a mistake, not a no-op'
}

test_skips_blanks_and_comments() {
  local out
  out="$(_run_targets "
# the site
service=devpulse-saas-serve=ghcr.io/thingzio/devpulse-site@${DIGEST}

")"
  assert_contains "${out}" 'count=1' 'blank lines and comments must not become targets'
}

test_honours_a_custom_remote_repository() {
  local out
  out="$(_run_targets "service=x-serve=ghcr.io/thingzio/img@${DIGEST}" REMOTE_REPOSITORY=mirror)"
  assert_contains "${out}" "us-west1-docker.pkg.dev/thingzio/mirror/thingzio/img@${DIGEST}" \
    'the remote repository name must be configurable'
}
