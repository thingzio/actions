# shellcheck shell=bash
#
# Tests for scripts/derive-tags.sh.
#
# Tag derivation decides what `latest` points at, so the interesting cases are
# the ones where a naive implementation would publish the wrong thing: a
# prerelease claiming `latest`, a branch name containing a slash, a caller
# smuggling a second tag through whitespace.

DERIVE_TAGS_SH="${REPO_ROOT}/scripts/derive-tags.sh"

# _derive runs the script with a clean environment, so a variable left over from
# the developer's shell (CI sets SHA and REF_NAME) cannot influence a test.
_derive() {
  local mode="$1"
  shift
  env -i \
    PATH="${PATH}" \
    HOME="${HOME}" \
    "$@" \
    bash "${DERIVE_TAGS_SH}" "${mode}"
}

## Semantic version tags

test_release_tag_fans_out_to_major_minor_and_latest() {
  run _derive release REF_TYPE=tag REF_NAME=v1.2.3
  assert_ok
  assert_stdout_eq "v1.2.3
v1.2
v1
latest"
}

test_release_tag_with_multi_digit_components() {
  run _derive release REF_TYPE=tag REF_NAME=v10.20.30
  assert_ok
  assert_stdout_eq "v10.20.30
v10.20
v10
latest"
}

test_zero_version_is_still_fanned_out() {
  run _derive release REF_TYPE=tag REF_NAME=v0.1.0
  assert_ok
  assert_stdout_eq "v0.1.0
v0.1
v0
latest"
}

# The whole point of separating prereleases: v1.2.3-rc.1 must never become what
# `latest` or `v1` resolves to.
test_prerelease_tag_does_not_claim_latest() {
  run _derive release REF_TYPE=tag REF_NAME=v1.2.3-rc.1
  assert_ok
  assert_stdout_eq "v1.2.3-rc.1"
  assert_not_contains "${RUN_OUT}" "latest"
}

test_prerelease_with_build_metadata_is_sanitized() {
  run _derive release REF_TYPE=tag REF_NAME=v1.2.3-rc.1+build.5
  assert_ok
  # "+" is not legal in an OCI tag, so it is rewritten rather than rejected.
  assert_stdout_eq "v1.2.3-rc.1-build.5"
}

test_non_semver_tag_is_passed_through() {
  run _derive release REF_TYPE=tag REF_NAME=nightly
  assert_ok
  assert_stdout_eq "nightly"
}

test_tag_ref_without_a_name_is_rejected() {
  run _derive release REF_TYPE=tag
  assert_failed
  assert_stderr_contains "REF_NAME is required"
}

## Branch pushes

test_branch_push_emits_a_short_sha() {
  run _derive release REF_TYPE=branch REF_NAME=feature \
    SHA=abcdef0123456789abcdef0123456789abcdef01
  assert_ok
  assert_stdout_eq "sha-abcdef0"
}

test_default_branch_push_also_emits_the_branch_name() {
  run _derive release REF_TYPE=branch REF_NAME=main DEFAULT_BRANCH=main \
    SHA=abcdef0123456789abcdef0123456789abcdef01
  assert_ok
  assert_stdout_eq "sha-abcdef0
main"
}

test_non_default_branch_does_not_emit_the_branch_name() {
  run _derive release REF_TYPE=branch REF_NAME=topic DEFAULT_BRANCH=main \
    SHA=abcdef0123456789abcdef0123456789abcdef01
  assert_ok
  assert_stdout_eq "sha-abcdef0"
}

# A default branch named "release/v2" is legal in git and illegal as an OCI tag.
test_slash_in_the_default_branch_is_sanitized() {
  run _derive release REF_TYPE=branch REF_NAME=release/v2 DEFAULT_BRANCH=release/v2 \
    SHA=abcdef0123456789abcdef0123456789abcdef01
  assert_ok
  assert_stdout_eq "sha-abcdef0
release-v2"
}

test_branch_push_rejects_a_short_sha() {
  run _derive release REF_TYPE=branch REF_NAME=main SHA=abcdef0
  assert_failed
  assert_stderr_contains "40-character"
}

test_branch_push_rejects_a_non_hex_sha() {
  run _derive release REF_TYPE=branch REF_NAME=main \
    SHA=ZZZZZZ0123456789abcdef0123456789abcdef01
  assert_failed
  assert_stderr_contains "commit SHA"
}

test_branch_push_rejects_a_missing_sha() {
  run _derive release REF_TYPE=branch REF_NAME=main
  assert_failed
  assert_stderr_contains "commit SHA"
}

## Pull requests

test_pull_request_emits_a_pr_tag() {
  run _derive release EVENT_NAME=pull_request REF_TYPE=branch PR_NUMBER=42
  assert_ok
  assert_stdout_eq "pr-42"
}

test_pull_request_rejects_a_non_numeric_number() {
  run _derive release EVENT_NAME=pull_request REF_TYPE=branch 'PR_NUMBER=42; rm -rf /'
  assert_failed
  assert_stderr_contains "numeric PR_NUMBER"
}

test_pull_request_rejects_a_missing_number() {
  run _derive release EVENT_NAME=pull_request REF_TYPE=branch
  assert_failed
  assert_stderr_contains "numeric PR_NUMBER"
}

# A tag push during a pull_request event is still a tag build.
test_tag_ref_takes_precedence_over_the_pull_request_event() {
  run _derive release EVENT_NAME=pull_request REF_TYPE=tag REF_NAME=v2.0.0 PR_NUMBER=7
  assert_ok
  assert_stdout_eq "v2.0.0
v2.0
v2
latest"
}

## Caller overrides

test_override_replaces_the_derived_set() {
  run _derive release TAGS_OVERRIDE=custom REF_TYPE=tag REF_NAME=v1.2.3
  assert_ok
  assert_stdout_eq "custom"
}

test_override_accepts_a_comma_separated_list() {
  run _derive release TAGS_OVERRIDE=one,two,three
  assert_ok
  assert_stdout_eq "one
two
three"
}

test_override_accepts_a_newline_separated_list() {
  run _derive release "TAGS_OVERRIDE=one
two"
  assert_ok
  assert_stdout_eq "one
two"
}

test_override_trims_whitespace() {
  run _derive release "TAGS_OVERRIDE=  one  ,  two  "
  assert_ok
  assert_stdout_eq "one
two"
}

test_override_removes_duplicates_preserving_order() {
  run _derive release TAGS_OVERRIDE=b,a,b,c,a
  assert_ok
  assert_stdout_eq "b
a
c"
}

test_override_of_only_separators_is_rejected() {
  run _derive release "TAGS_OVERRIDE=, ,"
  assert_failed
  assert_stderr_contains "no usable tag"
}

# Whitespace is stripped rather than treated as a separator, so a value like
# "good evil" cannot become two tags.
test_override_does_not_split_on_spaces() {
  run _derive release "TAGS_OVERRIDE=good evil"
  assert_ok
  assert_stdout_eq "goodevil"
}

test_override_rejects_a_tag_starting_with_a_dash() {
  run _derive release TAGS_OVERRIDE=-oops
  assert_failed
  assert_stderr_contains "is not a valid OCI tag"
}

test_override_rejects_a_tag_starting_with_a_dot() {
  run _derive release TAGS_OVERRIDE=.oops
  assert_failed
  assert_stderr_contains "is not a valid OCI tag"
}

test_override_rejects_a_tag_containing_a_slash() {
  run _derive release TAGS_OVERRIDE=org/name
  assert_failed
  assert_stderr_contains "is not a valid OCI tag"
}

test_override_rejects_a_tag_containing_a_colon() {
  run _derive release TAGS_OVERRIDE=name:tag
  assert_failed
  assert_stderr_contains "is not a valid OCI tag"
}

test_override_rejects_an_overlong_tag() {
  local long
  long="$(printf 'a%.0s' $(seq 129))"
  run _derive release "TAGS_OVERRIDE=${long}"
  assert_failed
  assert_stderr_contains "is not a valid OCI tag"
}

test_override_accepts_a_tag_of_exactly_128_characters() {
  local long
  long="$(printf 'a%.0s' $(seq 128))"
  run _derive release "TAGS_OVERRIDE=${long}"
  assert_ok
  assert_stdout_eq "${long}"
}

## Candidate tags

test_candidate_tag_uses_run_id_and_attempt() {
  run _derive candidate RUN_ID=123456 RUN_ATTEMPT=2
  assert_ok
  assert_stdout_eq "candidate-123456-2"
}

test_candidate_tag_rejects_a_non_numeric_run_id() {
  run _derive candidate 'RUN_ID=1; evil' RUN_ATTEMPT=1
  assert_failed
  assert_stderr_contains "RUN_ID must be numeric"
}

test_candidate_tag_rejects_a_non_numeric_attempt() {
  run _derive candidate RUN_ID=1 RUN_ATTEMPT=latest
  assert_failed
  assert_stderr_contains "RUN_ATTEMPT must be numeric"
}

test_candidate_tag_rejects_a_missing_run_id() {
  run _derive candidate RUN_ATTEMPT=1
  assert_failed
  assert_stderr_contains "RUN_ID must be numeric"
}

## Modes

test_unknown_mode_is_rejected() {
  run _derive publish
  assert_failed
  assert_stderr_contains "unknown mode"
}

test_release_is_the_default_mode() {
  run env -i PATH="${PATH}" HOME="${HOME}" REF_TYPE=tag REF_NAME=v3.0.0 \
    bash "${DERIVE_TAGS_SH}"
  assert_ok
  assert_contains "${RUN_OUT}" "v3.0.0"
}
