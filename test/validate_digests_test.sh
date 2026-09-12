# shellcheck shell=bash
#
# Tests for scripts/validate-digests.sh.
#
# Every failure this script catches is silent: the build is green, the image is
# pushed, and the attestation is signed against a subject that does not describe
# what a consumer will pull. These tests encode each of those shapes.

VALIDATE_SH="${REPO_ROOT}/scripts/validate-digests.sh"

A="sha256:1111111111111111111111111111111111111111111111111111111111111111"
B="sha256:2222222222222222222222222222222222222222222222222222222222222222"
C="sha256:3333333333333333333333333333333333333333333333333333333333333333"
IDX="sha256:0000000000000000000000000000000000000000000000000000000000000000"

_d() { run bash "${VALIDATE_SH}" "$@"; }

## Multi-platform builds

test_accepts_a_healthy_two_platform_index() {
  _d digests true "${IDX}" "${A}" "${B}"
  assert_ok
}

test_accepts_a_healthy_three_platform_index() {
  _d digests true "${IDX}" "${A}" "${B}" "${C}"
  assert_ok
}

# crane returns the reference's own digest when the reference is a plain image
# manifest, so a platform digest equal to the index means the "index" is not one.
test_rejects_a_platform_digest_equal_to_the_index() {
  _d digests true "${IDX}" "${IDX}" "${B}"
  assert_failed
  assert_stderr_contains "is not a multi-platform index"
}

test_rejects_a_later_platform_digest_equal_to_the_index() {
  _d digests true "${IDX}" "${A}" "${IDX}"
  assert_failed
  assert_stderr_contains "is not a multi-platform index"
}

# Two platforms resolving to one manifest means an architecture went missing.
test_rejects_identical_platform_digests() {
  _d digests true "${IDX}" "${A}" "${A}"
  assert_failed
  assert_stderr_contains "lost an architecture"
}

test_rejects_a_duplicate_among_three_platforms() {
  _d digests true "${IDX}" "${A}" "${B}" "${A}"
  assert_failed
  assert_stderr_contains "lost an architecture"
}

test_rejects_a_single_platform_when_an_index_is_expected() {
  _d digests true "${IDX}" "${A}"
  assert_failed
  assert_stderr_contains "only 1 platform digest"
}

## Single-platform builds

test_accepts_a_single_platform_build() {
  _d digests false "${A}" "${A}"
  assert_ok
}

test_single_platform_requires_the_digest_to_equal_the_index() {
  _d digests false "${IDX}" "${A}"
  assert_failed
  assert_stderr_contains "must equal the index digest"
}

test_single_platform_rejects_more_than_one_digest() {
  _d digests false "${IDX}" "${A}" "${B}"
  assert_failed
  assert_stderr_contains "has exactly one"
}

## Digest formatting

test_rejects_a_malformed_index_digest() {
  _d digests true "sha256:short" "${A}" "${B}"
  assert_failed
  assert_stderr_contains "index digest must be of the form"
}

test_rejects_a_digest_without_the_algorithm_prefix() {
  _d digests true "1111111111111111111111111111111111111111111111111111111111111111" "${A}" "${B}"
  assert_failed
  assert_stderr_contains "must be of the form"
}

test_rejects_an_uppercase_digest() {
  _d digests true "${IDX}" "sha256:AAAA111111111111111111111111111111111111111111111111111111111111" "${B}"
  assert_failed
  assert_stderr_contains "platform digest 1 must be of the form"
}

test_rejects_a_non_sha256_algorithm() {
  _d digests true "${IDX}" "sha512:1111111111111111111111111111111111111111111111111111111111111111" "${B}"
  assert_failed
  assert_stderr_contains "must be of the form"
}

test_rejects_a_digest_containing_a_newline() {
  _d digests true "${IDX}" "$(printf '%s\nevil=1' "${A}")" "${B}"
  assert_failed
  assert_stderr_contains "must not contain a newline"
}

test_rejects_an_invalid_expect_index_flag() {
  _d digests yes "${IDX}" "${A}" "${B}"
  assert_failed
  assert_stderr_contains "must be 'true' or 'false'"
}

test_requires_at_least_three_arguments() {
  _d digests true "${IDX}"
  assert_rc 2
  assert_stderr_contains "usage:"
}

## SBOM validation

_write_sbom() {
  local dir="$1" body="$2"
  printf '%s' "${body}" >"${dir}/sbom.json"
  printf '%s\n' "${dir}/sbom.json"
}

test_accepts_a_valid_cyclonedx_document() {
  local dir file
  dir="$(fixture_dir)"
  file="$(_write_sbom "${dir}" '{"bomFormat":"CycloneDX","specVersion":"1.6","components":[{"name":"libc"}]}')"
  _d sbom "${file}"
  assert_ok
  assert_stderr_contains "CycloneDX 1.6, 1 components"
  rm -rf "${dir}"
}

# The failure this check exists for: cosign would stamp the CycloneDX predicate
# type on an SPDX document and the referrers listing would still read correctly.
test_rejects_an_spdx_document() {
  local dir file
  dir="$(fixture_dir)"
  file="$(_write_sbom "${dir}" '{"spdxVersion":"SPDX-2.3","name":"app"}')"
  _d sbom "${file}"
  assert_failed
  assert_stderr_contains "want CycloneDX"
  rm -rf "${dir}"
}

test_rejects_a_wrong_bom_format() {
  local dir file
  dir="$(fixture_dir)"
  file="$(_write_sbom "${dir}" '{"bomFormat":"NotCycloneDX","specVersion":"1.6","components":[{"name":"x"}]}')"
  _d sbom "${file}"
  assert_failed
  assert_stderr_contains "want CycloneDX"
  rm -rf "${dir}"
}

test_rejects_a_document_without_a_spec_version() {
  local dir file
  dir="$(fixture_dir)"
  file="$(_write_sbom "${dir}" '{"bomFormat":"CycloneDX","components":[{"name":"x"}]}')"
  _d sbom "${file}"
  assert_failed
  assert_stderr_contains "no specVersion"
  rm -rf "${dir}"
}

# An empty component list nearly always means syft scanned the wrong reference.
test_rejects_a_document_with_no_components() {
  local dir file
  dir="$(fixture_dir)"
  file="$(_write_sbom "${dir}" '{"bomFormat":"CycloneDX","specVersion":"1.6","components":[]}')"
  _d sbom "${file}"
  assert_failed
  assert_stderr_contains "lists no components"
  rm -rf "${dir}"
}

test_rejects_a_document_with_a_missing_components_key() {
  local dir file
  dir="$(fixture_dir)"
  file="$(_write_sbom "${dir}" '{"bomFormat":"CycloneDX","specVersion":"1.6"}')"
  _d sbom "${file}"
  assert_failed
  assert_stderr_contains "lists no components"
  rm -rf "${dir}"
}

test_rejects_invalid_json() {
  local dir file
  dir="$(fixture_dir)"
  file="$(_write_sbom "${dir}" 'not json at all')"
  _d sbom "${file}"
  assert_failed
  assert_stderr_contains "not valid JSON"
  rm -rf "${dir}"
}

test_rejects_an_empty_file() {
  local dir
  dir="$(fixture_dir)"
  : >"${dir}/sbom.json"
  _d sbom "${dir}/sbom.json"
  assert_failed
  assert_stderr_contains "is empty"
  rm -rf "${dir}"
}

test_rejects_a_missing_file() {
  _d sbom "/nonexistent/sbom.json"
  assert_failed
  assert_stderr_contains "not found"
}

## dispatch

test_unknown_command_shows_usage() {
  _d nonsense
  assert_rc 2
  assert_stderr_contains "usage:"
}

test_no_command_shows_usage() {
  _d
  assert_rc 2
  assert_stderr_contains "usage:"
}
