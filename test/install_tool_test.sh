# shellcheck shell=bash
#
# Tests for scripts/install-tool.sh.
#
# Asset naming is the fragile part: four projects, three different conventions,
# and a wrong guess produces a 404 at release time rather than at review time.
# These tests pin the exact filenames against the real published assets, so a
# version bump that changes a naming convention fails here first.
#
# Nothing in this file downloads anything. describe_tool is sourced and called
# directly; the network paths are covered by common_test.sh via file:// URLs.

INSTALL_TOOL_SH="${REPO_ROOT}/scripts/install-tool.sh"

# _describe sources install-tool.sh in a subshell and prints the four fields
# describe_tool sets. The script guards its main() behind a BASH_SOURCE check
# precisely so it can be sourced here.
_describe() {
  bash -c "
    set -uo pipefail
    . '${INSTALL_TOOL_SH}'
    describe_tool '$1' '$2' '$3' '$4'
    printf '%s\n%s\n%s\n%s\n' \"\${BASE_URL}\" \"\${ARCHIVE}\" \"\${MANIFEST}\" \"\${BINARY}\"
  "
}

test_ko_linux_amd64_asset_names() {
  run _describe ko v0.19.1 linux amd64
  assert_ok
  assert_contains "${RUN_OUT}" "https://github.com/ko-build/ko/releases/download/v0.19.1"
  assert_contains "${RUN_OUT}" "ko_0.19.1_Linux_x86_64.tar.gz"
  assert_contains "${RUN_OUT}" "checksums.txt"
}

test_ko_linux_arm64_asset_names() {
  run _describe ko v0.19.1 linux arm64
  assert_ok
  assert_contains "${RUN_OUT}" "ko_0.19.1_Linux_arm64.tar.gz"
}

test_ko_darwin_arm64_asset_names() {
  run _describe ko v0.19.1 darwin arm64
  assert_ok
  assert_contains "${RUN_OUT}" "ko_0.19.1_Darwin_arm64.tar.gz"
}

# crane's archive carries the repository name, not the binary name, and has no
# version in it at all.
test_crane_asset_names() {
  run _describe crane v0.22.1 linux amd64
  assert_ok
  assert_contains "${RUN_OUT}" "https://github.com/google/go-containerregistry/releases/download/v0.22.1"
  assert_contains "${RUN_OUT}" "go-containerregistry_Linux_x86_64.tar.gz"
  assert_contains "${RUN_OUT}" "crane"
}

test_crane_darwin_asset_names() {
  run _describe crane v0.22.1 darwin arm64
  assert_ok
  assert_contains "${RUN_OUT}" "go-containerregistry_Darwin_arm64.tar.gz"
}

# syft uses lowercase os/arch and a version-qualified manifest name.
test_syft_asset_names() {
  run _describe syft v1.51.1 linux arm64
  assert_ok
  assert_contains "${RUN_OUT}" "https://github.com/anchore/syft/releases/download/v1.51.1"
  assert_contains "${RUN_OUT}" "syft_1.51.1_linux_arm64.tar.gz"
  assert_contains "${RUN_OUT}" "syft_1.51.1_checksums.txt"
}

test_syft_darwin_asset_names() {
  run _describe syft v1.51.1 darwin amd64
  assert_ok
  assert_contains "${RUN_OUT}" "syft_1.51.1_darwin_amd64.tar.gz"
}

test_actionlint_asset_names() {
  run _describe actionlint v1.7.12 linux amd64
  assert_ok
  assert_contains "${RUN_OUT}" "https://github.com/rhysd/actionlint/releases/download/v1.7.12"
  assert_contains "${RUN_OUT}" "actionlint_1.7.12_linux_amd64.tar.gz"
  assert_contains "${RUN_OUT}" "actionlint_1.7.12_checksums.txt"
}

test_unknown_tool_is_rejected() {
  run _describe totally-not-a-tool v1.0.0 linux amd64
  assert_failed
  assert_stderr_contains "unknown tool"
}

test_unsupported_architecture_is_rejected() {
  run _describe ko v0.19.1 linux s390x
  assert_failed
  assert_stderr_contains "unsupported architecture"
}

test_unsupported_os_is_rejected() {
  run _describe ko v0.19.1 plan9 amd64
  assert_failed
  assert_stderr_contains "unsupported operating system"
}

test_rejects_a_version_without_a_v_prefix() {
  run "${INSTALL_TOOL_SH}" ko 0.19.1 "$(fixture_dir)"
  assert_failed
  assert_stderr_contains "vMAJOR.MINOR.PATCH"
}

test_rejects_missing_arguments() {
  run "${INSTALL_TOOL_SH}" ko
  assert_rc 2
  assert_stderr_contains "usage:"
}

# The versions this repository actually pins must be installable. This is the
# one test that reaches the network; it proves the pinned version, the asset
# name and the published checksum all agree.
test_installs_the_pinned_actionlint_and_verifies_its_checksum() {
  local dir
  if [ -n "${THINGZ_SKIP_NETWORK_TESTS-}" ]; then
    return 0
  fi
  dir="$(fixture_dir)"
  run "${INSTALL_TOOL_SH}" actionlint "$("${REPO_ROOT}/scripts/versions.sh" tools.actionlint)" "${dir}"
  assert_ok
  if [ ! -x "${dir}/actionlint" ]; then
    printf 'actionlint was not installed into %s\n' "${dir}" >&2
    rm -rf "${dir}"
    return 1
  fi
  rm -rf "${dir}"
}
