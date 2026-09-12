# shellcheck shell=bash
#
# Tests for scripts/verify-checksums.sh.
#
# This script decides what a Sigstore signature and a SLSA provenance statement
# will claim. Every (digest, filename) pair it accepts becomes a subject
# attested under the reusable workflow's identity, so a line it lets through
# unchecked is a subject the build never produced, vouched for by a trusted
# builder. The interesting cases are all about what must NOT be accepted.

VERIFY_SH="${REPO_ROOT}/scripts/verify-checksums.sh"

# _fixture creates an assets directory holding two artifacts and echoes its
# path. The checksum file is written by each test, since that is what varies.
_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "${dir}/assets"
  printf 'alpha\n' > "${dir}/assets/app_1.0.0_linux_amd64.tar.gz"
  printf 'beta\n' > "${dir}/assets/app_1.0.0_darwin_arm64.tar.gz"
  printf '%s\n' "${dir}"
}

_digest() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

_checksums_for() {
  local dir="$1" name
  for name in "$2" "$3"; do
    [ -n "${name}" ] || continue
    printf '%s  %s\n' "$(_digest "${dir}/assets/${name}")" "${name}"
  done
}

_verify() { run bash "${VERIFY_SH}" "$1" "$2"; }

## agreement

test_accepts_checksums_that_describe_the_release() {
  local dir
  dir="$(_fixture)"
  _checksums_for "${dir}" app_1.0.0_linux_amd64.tar.gz app_1.0.0_darwin_arm64.tar.gz \
    > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_ok
  assert_stdout_eq "verified 2 artifact(s) against ${dir}/assets"
}

# goreleaser uploads the checksum file itself as a release asset, so the assets
# directory always holds a file the checksum file does not name. That is not a
# discrepancy.
test_ignores_release_assets_the_checksum_file_does_not_name() {
  local dir
  dir="$(_fixture)"
  _checksums_for "${dir}" app_1.0.0_linux_amd64.tar.gz "" > "${dir}/checksums.txt"
  cp "${dir}/checksums.txt" "${dir}/assets/checksums.txt"
  printf 'a bundle\n' > "${dir}/assets/checksums.txt.bundle"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_ok
}

test_accepts_binary_mode_lines() {
  local dir
  dir="$(_fixture)"
  printf '%s *%s\n' \
    "$(_digest "${dir}/assets/app_1.0.0_linux_amd64.tar.gz")" \
    app_1.0.0_linux_amd64.tar.gz > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_ok
}

test_accepts_an_uppercase_digest() {
  local dir upper
  dir="$(_fixture)"
  upper="$(_digest "${dir}/assets/app_1.0.0_linux_amd64.tar.gz" | tr 'a-f' 'A-F')"
  printf '%s  %s\n' "${upper}" app_1.0.0_linux_amd64.tar.gz > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_ok
}

test_ignores_blank_lines() {
  local dir
  dir="$(_fixture)"
  {
    printf '\n'
    _checksums_for "${dir}" app_1.0.0_linux_amd64.tar.gz ""
    printf '\n'
  } > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_ok
}

test_reads_a_final_line_with_no_newline() {
  local dir
  dir="$(_fixture)"
  printf '%s  %s' \
    "$(_digest "${dir}/assets/app_1.0.0_linux_amd64.tar.gz")" \
    app_1.0.0_linux_amd64.tar.gz > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_ok
  assert_stdout_eq "verified 1 artifact(s) against ${dir}/assets"
}

## the reason this script exists

# The build job runs the caller's goreleaser hooks. A line naming a file that
# is not on the release is provenance vouching for bytes the build never
# produced, under the reusable workflow's identity.
test_rejects_a_subject_that_is_not_on_the_release() {
  local dir
  dir="$(_fixture)"
  {
    _checksums_for "${dir}" app_1.0.0_linux_amd64.tar.gz ""
    printf '%064d  smuggled.tar.gz\n' 7
  } > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_failed
  assert_stderr_contains "smuggled.tar.gz"
  assert_stderr_contains "never produced"
}

test_rejects_a_digest_that_does_not_match_the_artifact() {
  local dir
  dir="$(_fixture)"
  printf '%064d  %s\n' 0 app_1.0.0_linux_amd64.tar.gz > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_failed
  assert_stderr_contains "does not match its digest"
}

# An artifact replaced after the checksum file was written is the failure this
# catches that nothing else would.
test_rejects_an_artifact_modified_after_the_checksums_were_written() {
  local dir
  dir="$(_fixture)"
  _checksums_for "${dir}" app_1.0.0_linux_amd64.tar.gz app_1.0.0_darwin_arm64.tar.gz \
    > "${dir}/checksums.txt"
  printf 'swapped\n' > "${dir}/assets/app_1.0.0_darwin_arm64.tar.gz"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_failed
  assert_stderr_contains "app_1.0.0_darwin_arm64.tar.gz"
}

# `sha256sum --check` exits 0 on an empty file. Without an explicit check, an
# empty checksum file would be signed and attested while committing to nothing.
test_rejects_an_empty_checksum_file() {
  local dir
  dir="$(_fixture)"
  : > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_failed
  assert_stderr_contains "commit to nothing"
}

test_rejects_a_checksum_file_of_only_blank_lines() {
  local dir
  dir="$(_fixture)"
  printf '\n\n\n' > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_failed
  assert_stderr_contains "commit to nothing"
}

## malformed input is rejected, never skipped

test_rejects_a_line_that_is_not_a_checksum() {
  local dir
  dir="$(_fixture)"
  {
    _checksums_for "${dir}" app_1.0.0_linux_amd64.tar.gz ""
    printf 'this is not a checksum line\n'
  } > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_failed
  assert_stderr_contains "malformed line"
}

test_rejects_a_digest_of_the_wrong_length() {
  local dir
  dir="$(_fixture)"
  printf 'abc123  %s\n' app_1.0.0_linux_amd64.tar.gz > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_failed
  assert_stderr_contains "non-sha256 digest"
}

test_rejects_a_line_with_no_filename() {
  local dir
  dir="$(_fixture)"
  printf '%064d  \n' 0 > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_failed
  assert_stderr_contains "no filename"
}

# A relative path escaping the assets directory would let a line satisfy the
# existence check against a file the release does not carry.
test_rejects_a_name_that_escapes_the_assets_directory() {
  local dir
  dir="$(_fixture)"
  printf '%064d  ../../etc/hosts\n' 0 > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_failed
  assert_stderr_contains "outside the release"
}

test_rejects_an_absolute_name() {
  local dir
  dir="$(_fixture)"
  printf '%064d  /etc/hosts\n' 0 > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/assets"
  assert_failed
  assert_stderr_contains "outside the release"
}

## arguments

test_rejects_a_missing_checksum_file() {
  local dir
  dir="$(_fixture)"
  _verify "${dir}/absent.txt" "${dir}/assets"
  assert_failed
  assert_stderr_contains "cannot read checksum file"
}

test_rejects_a_missing_assets_directory() {
  local dir
  dir="$(_fixture)"
  _checksums_for "${dir}" app_1.0.0_linux_amd64.tar.gz "" > "${dir}/checksums.txt"
  _verify "${dir}/checksums.txt" "${dir}/absent"
  assert_failed
  assert_stderr_contains "cannot read assets directory"
}

test_requires_both_arguments() {
  run bash "${VERIFY_SH}" only-one
  assert_failed
}
