# shellcheck shell=bash
#
# Tests for scripts/versions.sh, the awk reader that makes .versions.yaml the
# single source of truth for local development and CI alike.

VERSIONS_SH="${REPO_ROOT}/scripts/versions.sh"

_fixture() {
  local dir
  dir="$(fixture_dir)"
  cat >"${dir}/.versions.yaml" <<'YAML'
# A comment at the top.

tools:
  ko: v0.19.1
  cosign: v3.1.3   # trailing comment must not become part of the value
  quoted: "v1.2.3"

images:
  ko_default_base: cgr.dev/chainguard/static:latest
  pinned: ghcr.io/thingzio/base:v1@sha256:abc
YAML
  printf '%s\n' "${dir}"
}

test_reads_a_plain_value() {
  local dir
  dir="$(_fixture)"
  run "${VERSIONS_SH}" tools.ko "${dir}/.versions.yaml"
  assert_ok
  assert_stdout_eq "v0.19.1"
  rm -rf "${dir}"
}

test_strips_trailing_comments() {
  local dir
  dir="$(_fixture)"
  run "${VERSIONS_SH}" tools.cosign "${dir}/.versions.yaml"
  assert_ok
  assert_stdout_eq "v3.1.3"
  rm -rf "${dir}"
}

test_strips_surrounding_quotes() {
  local dir
  dir="$(_fixture)"
  run "${VERSIONS_SH}" tools.quoted "${dir}/.versions.yaml"
  assert_ok
  assert_stdout_eq "v1.2.3"
  rm -rf "${dir}"
}

test_preserves_colons_inside_a_value() {
  local dir
  dir="$(_fixture)"
  run "${VERSIONS_SH}" images.ko_default_base "${dir}/.versions.yaml"
  assert_ok
  assert_stdout_eq "cgr.dev/chainguard/static:latest"
  rm -rf "${dir}"
}

test_preserves_a_digest_pinned_reference() {
  local dir
  dir="$(_fixture)"
  run "${VERSIONS_SH}" images.pinned "${dir}/.versions.yaml"
  assert_ok
  assert_stdout_eq "ghcr.io/thingzio/base:v1@sha256:abc"
  rm -rf "${dir}"
}

# A key that exists under a different section must not be found. Without the
# section guard, "tools.ko_default_base" would silently resolve.
test_does_not_cross_section_boundaries() {
  local dir
  dir="$(_fixture)"
  run "${VERSIONS_SH}" tools.ko_default_base "${dir}/.versions.yaml"
  assert_failed
  assert_stderr_contains "not found"
  rm -rf "${dir}"
}

test_fails_on_a_missing_key() {
  local dir
  dir="$(_fixture)"
  run "${VERSIONS_SH}" tools.nope "${dir}/.versions.yaml"
  assert_failed
  assert_stderr_contains "tools.nope not found"
  rm -rf "${dir}"
}

test_fails_on_a_missing_file() {
  run "${VERSIONS_SH}" tools.ko "/nonexistent/.versions.yaml"
  assert_failed
  assert_stderr_contains "cannot read"
}

test_rejects_a_key_without_a_section() {
  local dir
  dir="$(_fixture)"
  run "${VERSIONS_SH}" ko "${dir}/.versions.yaml"
  assert_rc 2
  assert_stderr_contains "must be <section>.<name>"
  rm -rf "${dir}"
}

test_rejects_no_arguments() {
  run "${VERSIONS_SH}"
  assert_rc 2
  assert_stderr_contains "usage:"
}

# The real file is the contract every workflow depends on. If a key here is
# renamed, this fails before CI does.
test_repository_versions_file_exposes_the_required_keys() {
  local key
  for key in tools.ko tools.crane tools.syft tools.cosign tools.actionlint \
    tools.yamllint tools.shellcheck tools.zizmor tools.trivy tools.golangci_lint \
    images.ko_default_base \
    checksums.shellcheck_linux_amd64 checksums.shellcheck_darwin_arm64; do
    run "${VERSIONS_SH}" "${key}"
    assert_ok "${key} must resolve from the repository .versions.yaml" || return 1
    assert_ne "" "${RUN_OUT}" "${key} must not be empty" || return 1
  done
}

# Cosign below v3.1.0 logs DSSE attestations as the legacy Rekor entry type,
# which sigstore-go cannot verify. Guard the floor so a bump cannot regress it.
test_cosign_version_is_at_least_3_1_0() {
  local v major minor
  v="$("${VERSIONS_SH}" tools.cosign)"
  assert_contains "${v}" "v" "cosign version should be v-prefixed"
  v="${v#v}"
  major="${v%%.*}"
  minor="${v#*.}"
  minor="${minor%%.*}"
  if [ "${major}" -lt 3 ] || { [ "${major}" -eq 3 ] && [ "${minor}" -lt 1 ]; }; then
    printf 'cosign must be >= v3.1.0 for Rekor v2 hashedrekord/PAE, got v%s\n' "${v}" >&2
    return 1
  fi
}
