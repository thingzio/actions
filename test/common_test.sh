# shellcheck shell=bash
#
# Tests for scripts/lib/common.sh. The checksum helpers are the security-critical
# part: they are the only thing standing between a compromised release asset and
# a binary running inside the trusted builder.

COMMON_SH="${REPO_ROOT}/scripts/lib/common.sh"

# Helpers that call die() must run in a subshell, because die() exits. _in_subshell
# wraps a snippet so run() can capture its status.
_bash_snippet() {
  bash -c "set -uo pipefail; . '${COMMON_SH}'; $1"
}

test_sha256_of_matches_a_known_vector() {
  local dir
  dir="$(fixture_dir)"
  printf 'abc' >"${dir}/f"
  run _bash_snippet "sha256_of '${dir}/f'"
  assert_ok
  assert_stdout_eq "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  rm -rf "${dir}"
}

test_sha256_from_manifest_returns_the_matching_checksum() {
  local dir
  dir="$(fixture_dir)"
  cat >"${dir}/checksums.txt" <<'EOF'
1111111111111111111111111111111111111111111111111111111111111111  syft_1.51.1_linux_amd64.tar.gz
2222222222222222222222222222222222222222222222222222222222222222  syft_1.51.1_linux_arm64.tar.gz
EOF
  run _bash_snippet "sha256_from_manifest '${dir}/checksums.txt' 'syft_1.51.1_linux_arm64.tar.gz'"
  assert_ok
  assert_stdout_eq "2222222222222222222222222222222222222222222222222222222222222222"
  rm -rf "${dir}"
}

test_sha256_from_manifest_strips_the_binary_marker() {
  local dir
  dir="$(fixture_dir)"
  printf '3333333333333333333333333333333333333333333333333333333333333333 *ko_0.19.1_Linux_x86_64.tar.gz\n' \
    >"${dir}/checksums.txt"
  run _bash_snippet "sha256_from_manifest '${dir}/checksums.txt' 'ko_0.19.1_Linux_x86_64.tar.gz'"
  assert_ok
  assert_stdout_eq "3333333333333333333333333333333333333333333333333333333333333333"
  rm -rf "${dir}"
}

# The reason this helper compares whole filename fields instead of grepping:
# "syft_1.51.1_linux_amd64.tar.gz" is a substring-adjacent neighbour of
# "syft_1.51.1_linux_amd64.tar.gz.sbom", and verifying the wrong artifact's
# checksum is worse than not verifying at all.
test_sha256_from_manifest_does_not_match_a_longer_filename() {
  local dir
  dir="$(fixture_dir)"
  cat >"${dir}/checksums.txt" <<'EOF'
4444444444444444444444444444444444444444444444444444444444444444  syft_1.51.1_linux_amd64.tar.gz.sbom
EOF
  run _bash_snippet "sha256_from_manifest '${dir}/checksums.txt' 'syft_1.51.1_linux_amd64.tar.gz'"
  assert_failed
  assert_stderr_contains "found 0"
  rm -rf "${dir}"
}

test_sha256_from_manifest_rejects_duplicate_entries() {
  local dir
  dir="$(fixture_dir)"
  cat >"${dir}/checksums.txt" <<'EOF'
5555555555555555555555555555555555555555555555555555555555555555  tool.tar.gz
6666666666666666666666666666666666666666666666666666666666666666  tool.tar.gz
EOF
  run _bash_snippet "sha256_from_manifest '${dir}/checksums.txt' 'tool.tar.gz'"
  assert_failed
  assert_stderr_contains "found 2"
  rm -rf "${dir}"
}

test_sha256_from_manifest_fails_on_an_unreadable_manifest() {
  run _bash_snippet "sha256_from_manifest '/nonexistent/checksums.txt' 'tool.tar.gz'"
  assert_failed
  assert_stderr_contains "not readable"
}

test_download_verified_accepts_a_matching_checksum() {
  local dir sum
  dir="$(fixture_dir)"
  printf 'payload' >"${dir}/src"
  sum="$(_bash_snippet "sha256_of '${dir}/src'")"
  run _bash_snippet "download_verified 'file://${dir}/src' '${dir}/dest' '${sum}'"
  assert_ok
  assert_eq "payload" "$(cat "${dir}/dest")"
  rm -rf "${dir}"
}

test_download_verified_rejects_a_mismatched_checksum() {
  local dir
  dir="$(fixture_dir)"
  printf 'payload' >"${dir}/src"
  run _bash_snippet "download_verified 'file://${dir}/src' '${dir}/dest' '$(printf '0%.0s' $(seq 64))'"
  assert_failed
  assert_stderr_contains "checksum mismatch"
  rm -rf "${dir}"
}

# A failed verification must not leave a usable binary behind, or a later step
# could still execute it.
test_download_verified_removes_the_file_on_mismatch() {
  local dir
  dir="$(fixture_dir)"
  printf 'payload' >"${dir}/src"
  run _bash_snippet "download_verified 'file://${dir}/src' '${dir}/dest' '$(printf '0%.0s' $(seq 64))'"
  assert_failed
  if [ -e "${dir}/dest" ]; then
    printf 'download_verified left %s in place after a checksum mismatch\n' "${dir}/dest" >&2
    rm -rf "${dir}"
    return 1
  fi
  rm -rf "${dir}"
}

test_download_verified_rejects_a_non_hex_checksum() {
  run _bash_snippet "download_verified 'file:///dev/null' '/dev/null' 'not-a-checksum'"
  assert_failed
  assert_stderr_contains "lowercase hex sha256"
}

test_download_verified_rejects_a_short_checksum() {
  run _bash_snippet "download_verified 'file:///dev/null' '/dev/null' 'abcdef'"
  assert_failed
  assert_stderr_contains "64-character"
}

test_download_verified_fails_on_an_unreachable_url() {
  run _bash_snippet "download_verified 'file:///nonexistent/nope' '/tmp/out' '$(printf 'a%.0s' $(seq 64))'"
  assert_failed
  assert_stderr_contains "download failed"
}

test_require_no_newline_accepts_a_single_line() {
  run _bash_snippet "require_no_newline image 'ghcr.io/thingzio/app'"
  assert_ok
}

test_require_no_newline_rejects_an_embedded_newline() {
  run _bash_snippet "require_no_newline image \$'ghcr.io/app\nevil=1'"
  assert_failed
  assert_stderr_contains "must not contain a newline"
}

test_require_no_newline_rejects_a_carriage_return() {
  run _bash_snippet "require_no_newline image \$'ghcr.io/app\revil=1'"
  assert_failed
  assert_stderr_contains "must not contain a newline"
}

test_require_set_rejects_an_empty_value() {
  run _bash_snippet "require_set image ''"
  assert_failed
  assert_stderr_contains "image is required"
}

test_emit_output_writes_to_the_github_output_file() {
  local dir
  dir="$(fixture_dir)"
  run _bash_snippet "GITHUB_OUTPUT='${dir}/out' emit_output digest 'sha256:abc'"
  assert_ok
  assert_eq "digest=sha256:abc" "$(cat "${dir}/out")"
  rm -rf "${dir}"
}

# A newline in an output value could forge additional step outputs.
test_emit_output_rejects_a_multiline_value() {
  local dir
  dir="$(fixture_dir)"
  run _bash_snippet "GITHUB_OUTPUT='${dir}/out' emit_output digest \$'sha256:abc\npush=true'"
  assert_failed
  assert_stderr_contains "must not contain a newline"
  rm -rf "${dir}"
}

test_emit_multiline_output_uses_a_heredoc_delimiter() {
  local dir content
  dir="$(fixture_dir)"
  run _bash_snippet "GITHUB_OUTPUT='${dir}/out' emit_multiline_output tags \$'v1.2.3\nlatest'"
  assert_ok
  content="$(cat "${dir}/out")"
  assert_contains "${content}" "tags<<ghadelim_"
  assert_contains "${content}" "v1.2.3"
  assert_contains "${content}" "latest"
  rm -rf "${dir}"
}

test_host_arch_normalizes_to_amd64_or_arm64() {
  run _bash_snippet "host_arch"
  assert_ok
  case "${RUN_OUT}" in
    amd64 | arm64) return 0 ;;
  esac
  printf 'host_arch returned an unexpected value: %s\n' "${RUN_OUT}" >&2
  return 1
}

test_host_os_normalizes_to_linux_or_darwin() {
  run _bash_snippet "host_os"
  assert_ok
  case "${RUN_OUT}" in
    linux | darwin) return 0 ;;
  esac
  printf 'host_os returned an unexpected value: %s\n' "${RUN_OUT}" >&2
  return 1
}
