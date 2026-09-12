# shellcheck shell=bash
#
# Tests for scripts/actions/ko-build.sh.
#
# The reason this file exists: the selftest failed on its own fixture labels
# with "invalid label flag:  not for use". ko's --image-label is a pflag string
# slice parsed with encoding/csv, so a label value containing a comma is torn
# into fragments. A description containing a comma is completely ordinary, so
# this is a bug every consumer would eventually hit.
#
# The argument vector used to be built inline in the workflow, where nothing
# linted it and nothing could test it. These tests are the reason it moved.

KO_BUILD_SH="${REPO_ROOT}/scripts/actions/ko-build.sh"

_args() {
  run env -i \
    PATH="${PATH}" HOME="${HOME}" \
    KO_ARGS_ONLY=1 \
    CREATED=2026-01-01T00:00:00Z \
    MAIN=. \
    PLATFORMS=linux/amd64,linux/arm64 \
    CANDIDATE_TAG=candidate-1-1 \
    PRIMARY_TAG=v1.2.3 \
    SOURCE_URL=https://github.com/thingzio/app \
    REVISION=abc123 \
    PUSH=true \
    "$@" \
    bash "${KO_BUILD_SH}"
}

test_builds_the_expected_base_command() {
  _args EXTRA_LABELS= KO_FLAGS=
  assert_ok
  assert_contains "${RUN_OUT}" "build"
  assert_contains "${RUN_OUT}" "--bare"
  assert_contains "${RUN_OUT}" "--platform=linux/amd64,linux/arm64"
  assert_contains "${RUN_OUT}" "--tags=candidate-1-1"
}

test_adds_the_standard_oci_labels() {
  _args EXTRA_LABELS= KO_FLAGS=
  assert_ok
  assert_contains "${RUN_OUT}" '--image-label="org.opencontainers.image.source=https://github.com/thingzio/app"'
  assert_contains "${RUN_OUT}" '--image-label="org.opencontainers.image.revision=abc123"'
  assert_contains "${RUN_OUT}" '--image-label="org.opencontainers.image.version=v1.2.3"'
  assert_contains "${RUN_OUT}" '--image-label="org.opencontainers.image.created=2026-01-01T00:00:00Z"'
}

# The regression this file was created for.
test_quotes_a_label_value_containing_a_comma() {
  _args "EXTRA_LABELS=org.opencontainers.image.description=Fixture image, not for use" KO_FLAGS=
  assert_ok
  assert_contains "${RUN_OUT}" '--image-label="org.opencontainers.image.description=Fixture image, not for use"'
}

# The failure mode if quoting were dropped: ko splits on the comma and rejects
# the fragment. Assert the fragment never appears as its own argument.
test_a_comma_label_does_not_become_two_arguments() {
  _args "EXTRA_LABELS=org.opencontainers.image.description=one, two" KO_FLAGS=
  assert_ok
  assert_not_contains "${RUN_OUT}" '--image-label=" two"'
  assert_eq "1" "$(printf '%s\n' "${RUN_OUT}" | grep -c 'image.description')"
}

test_doubles_an_embedded_quote_per_csv_rules() {
  _args 'EXTRA_LABELS=org.example.note=say "hi", then go' KO_FLAGS=
  assert_ok
  assert_contains "${RUN_OUT}" '--image-label="org.example.note=say ""hi"", then go"'
}

test_handles_multiple_extra_labels() {
  _args "EXTRA_LABELS=$(printf 'a=1\nb=2')" KO_FLAGS=
  assert_ok
  assert_contains "${RUN_OUT}" '--image-label="a=1"'
  assert_contains "${RUN_OUT}" '--image-label="b=2"'
}

test_skips_blank_label_lines() {
  _args "EXTRA_LABELS=$(printf 'a=1\n\n\nb=2')" KO_FLAGS=
  assert_ok
  assert_eq "2" "$(printf '%s\n' "${RUN_OUT}" | grep -cE '^--image-label="(a|b)=')"
}

test_appends_allowlisted_ko_flags() {
  _args EXTRA_LABELS= "KO_FLAGS=$(printf -- '--image-user=65532\n--debug')"
  assert_ok
  assert_contains "${RUN_OUT}" "--image-user=65532"
  assert_contains "${RUN_OUT}" "--debug"
}

test_disables_push_when_not_publishing() {
  run env -i PATH="${PATH}" HOME="${HOME}" KO_ARGS_ONLY=1 \
    CREATED=2026-01-01T00:00:00Z MAIN=. PLATFORMS=linux/amd64 \
    CANDIDATE_TAG=candidate-1-1 PRIMARY_TAG=v1 SOURCE_URL=u REVISION=r \
    PUSH=false EXTRA_LABELS= KO_FLAGS= \
    bash "${KO_BUILD_SH}"
  assert_ok
  assert_contains "${RUN_OUT}" "--push=false"
}

test_does_not_disable_push_when_publishing() {
  _args EXTRA_LABELS= KO_FLAGS=
  assert_ok
  assert_not_contains "${RUN_OUT}" "--push=false"
}

# main is a package path. A value starting with "-" would be read by ko as a
# flag, which is the one shape that could smuggle an option past the allowlist.
test_rejects_a_main_that_looks_like_a_flag() {
  _args MAIN=--push EXTRA_LABELS= KO_FLAGS=
  assert_failed
  assert_stderr_contains "must be a package path, not a flag"
}

test_rejects_a_main_containing_a_newline() {
  _args "MAIN=$(printf '.\n--push')" EXTRA_LABELS= KO_FLAGS=
  assert_failed
  assert_stderr_contains "must not contain a newline"
}

test_rejects_an_empty_main() {
  _args MAIN= EXTRA_LABELS= KO_FLAGS=
  assert_failed
  assert_stderr_contains "main is required"
}
