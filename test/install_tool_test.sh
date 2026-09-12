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

# _describe sources install-tool.sh in a subshell and prints the five fields
# describe_tool sets, one per line, in a fixed order:
#
#   1 BASE_URL   2 ARCHIVE   3 MANIFEST   4 BINARY   5 ARCHIVE_PATH
#
# The order is load-bearing for the tests that index a specific line. The script
# guards its main() behind a BASH_SOURCE check precisely so it can be sourced.
_describe() {
  bash -c "
    set -uo pipefail
    . '${INSTALL_TOOL_SH}'
    describe_tool '$1' '$2' '$3' '$4'
    printf '%s\n%s\n%s\n%s\n%s\n' \
      \"\${BASE_URL}\" \"\${ARCHIVE}\" \"\${MANIFEST}\" \"\${BINARY}\" \"\${ARCHIVE_PATH}\"
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

# Trivy names its archives after neither GOARCH nor goreleaser's convention:
# "macOS" rather than "Darwin", and "64bit"/"ARM64" rather than amd64/arm64.
# Getting any of those wrong produces a 404 at install time, not a wrong binary,
# so these assertions are the cheapest place to catch a rename.
test_trivy_asset_names() {
  run _describe trivy v0.74.0 linux amd64
  assert_ok
  assert_contains "${RUN_OUT}" "https://github.com/aquasecurity/trivy/releases/download/v0.74.0"
  assert_contains "${RUN_OUT}" "trivy_0.74.0_Linux-64bit.tar.gz"
  assert_contains "${RUN_OUT}" "trivy_0.74.0_checksums.txt"
}

test_trivy_linux_arm64_asset_names() {
  run _describe trivy v0.74.0 linux arm64
  assert_ok
  assert_contains "${RUN_OUT}" "trivy_0.74.0_Linux-ARM64.tar.gz"
}

test_trivy_darwin_asset_names() {
  run _describe trivy v0.74.0 darwin arm64
  assert_ok
  assert_contains "${RUN_OUT}" "trivy_0.74.0_macOS-ARM64.tar.gz"
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

# ShellCheck is the odd one out: GNU-style arch names, a "v" in the archive
# name, the binary nested in a versioned directory, and no checksum manifest at
# all -- which is why its digest is pinned in .versions.yaml instead.
test_shellcheck_asset_names() {
  run _describe shellcheck v0.11.0 linux amd64
  assert_ok
  assert_contains "${RUN_OUT}" "https://github.com/koalaman/shellcheck/releases/download/v0.11.0"
  assert_contains "${RUN_OUT}" "shellcheck-v0.11.0.linux.x86_64.tar.gz"
  assert_contains "${RUN_OUT}" "shellcheck-v0.11.0/shellcheck"
}

test_shellcheck_uses_gnu_architecture_names() {
  run _describe shellcheck v0.11.0 linux arm64
  assert_ok
  assert_contains "${RUN_OUT}" "shellcheck-v0.11.0.linux.aarch64.tar.gz"
}

test_shellcheck_darwin_asset_names() {
  run _describe shellcheck v0.11.0 darwin arm64
  assert_ok
  assert_contains "${RUN_OUT}" "shellcheck-v0.11.0.darwin.aarch64.tar.gz"
}

# An empty MANIFEST is the signal to read the pinned digest from .versions.yaml
# rather than fetch a checksums file. Getting this backwards would silently skip
# verification, so assert the field is genuinely empty.
test_shellcheck_declares_no_checksum_manifest() {
  local manifest
  manifest="$(_describe shellcheck v0.11.0 linux amd64 | sed -n '3p')"
  assert_eq "" "${manifest}" "shellcheck must declare no checksum manifest"
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

# goreleaser uses the capitalized "Linux_x86_64" archive vocabulary rather than
# the lowercase names syft and actionlint publish, so the asset name is the
# thing most likely to be wrong. These pin it without the network, so a mistake
# is caught by `make test-offline` rather than only by a release.
test_goreleaser_linux_amd64_asset_names() {
  run _describe goreleaser v2.18.1 linux amd64
  assert_ok
  assert_contains "${RUN_OUT}" "https://github.com/goreleaser/goreleaser/releases/download/v2.18.1"
  assert_contains "${RUN_OUT}" "goreleaser_Linux_x86_64.tar.gz"
  assert_contains "${RUN_OUT}" "checksums.txt"
}

test_goreleaser_linux_arm64_asset_names() {
  run _describe goreleaser v2.18.1 linux arm64
  assert_ok
  assert_contains "${RUN_OUT}" "goreleaser_Linux_arm64.tar.gz"
}

test_goreleaser_darwin_arm64_asset_names() {
  run _describe goreleaser v2.18.1 darwin arm64
  assert_ok
  assert_contains "${RUN_OUT}" "goreleaser_Darwin_arm64.tar.gz"
}

# Reaching the network is the only way to know the pinned version, the asset
# name and the published checksum actually agree.
test_installs_the_pinned_goreleaser_and_verifies_its_checksum() {
  local dir
  if [ -n "${THINGZ_SKIP_NETWORK_TESTS-}" ]; then
    return 0
  fi
  dir="$(fixture_dir)"
  run "${INSTALL_TOOL_SH}" goreleaser "$("${REPO_ROOT}/scripts/versions.sh" tools.goreleaser)" "${dir}"
  assert_ok
  if [ ! -x "${dir}/goreleaser" ]; then
    printf 'goreleaser was not installed into %s\n' "${dir}" >&2
    rm -rf "${dir}"
    return 1
  fi
  rm -rf "${dir}"
}

test_install_tool_rejects_an_unknown_tool() {
  run "${INSTALL_TOOL_SH}" notatool v1.0.0 "$(fixture_dir)"
  assert_failed
}
