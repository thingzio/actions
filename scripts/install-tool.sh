#!/usr/bin/env bash
#
# Installs a pinned release binary into a directory, verifying its SHA-256
# against the checksum manifest the project publishes alongside it.
#
#   scripts/install-tool.sh ko         v0.19.1  .bin
#   scripts/install-tool.sh crane      v0.22.1  /usr/local/bin
#   scripts/install-tool.sh syft       v1.51.1  .bin
#   scripts/install-tool.sh actionlint v1.7.12  .bin
#
# This is the only sanctioned way to bring a binary onto a runner. There is no
# `curl | bash` anywhere in this repository: a piped installer executes before
# anything can be verified, which is precisely the supply-chain step these
# workflows exist to make auditable.
#
# Every project below names its artifacts differently -- ko and crane use
# goreleaser's capitalized "Linux_x86_64", syft and actionlint use lowercase
# "linux_amd64", and only ko and crane call the manifest plain "checksums.txt".
# The mapping lives here so callers never have to know.
#
# Installing an already-present binary of the same version is a no-op, so the
# script is safe to call repeatedly.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

usage() {
  printf 'usage: %s <ko|crane|syft|actionlint> <version> <dest-dir>\n' "${0##*/}" >&2
  exit 2
}

# goreleaser_arch maps a normalized arch to the capitalized vocabulary used by
# goreleaser's default archive names.
goreleaser_arch() {
  case "$1" in
    amd64) printf 'x86_64\n' ;;
    arm64) printf 'arm64\n' ;;
    *) die "unsupported architecture: $1" ;;
  esac
}

goreleaser_os() {
  case "$1" in
    linux) printf 'Linux\n' ;;
    darwin) printf 'Darwin\n' ;;
    *) die "unsupported operating system: $1" ;;
  esac
}

# describe_tool sets BASE_URL, ARCHIVE, MANIFEST and BINARY for the requested
# tool. Uses globals because bash 3.2, which is what macOS ships, has no
# associative arrays and no way to return a record.
describe_tool() {
  local tool="$1" version="$2" os="$3" arch="$4" bare="${2#v}"

  case "${tool}" in
    ko)
      BASE_URL="https://github.com/ko-build/ko/releases/download/${version}"
      ARCHIVE="ko_${bare}_$(goreleaser_os "${os}")_$(goreleaser_arch "${arch}").tar.gz"
      MANIFEST="checksums.txt"
      BINARY="ko"
      ;;
    crane)
      BASE_URL="https://github.com/google/go-containerregistry/releases/download/${version}"
      ARCHIVE="go-containerregistry_$(goreleaser_os "${os}")_$(goreleaser_arch "${arch}").tar.gz"
      MANIFEST="checksums.txt"
      BINARY="crane"
      ;;
    syft)
      BASE_URL="https://github.com/anchore/syft/releases/download/${version}"
      ARCHIVE="syft_${bare}_${os}_${arch}.tar.gz"
      MANIFEST="syft_${bare}_checksums.txt"
      BINARY="syft"
      ;;
    actionlint)
      BASE_URL="https://github.com/rhysd/actionlint/releases/download/${version}"
      ARCHIVE="actionlint_${bare}_${os}_${arch}.tar.gz"
      MANIFEST="actionlint_${bare}_checksums.txt"
      BINARY="actionlint"
      ;;
    *)
      die "unknown tool '${tool}'; expected one of ko, crane, syft, actionlint"
      ;;
  esac
}

installed_version_matches() {
  local binary="$1" want="$2" reported
  [ -x "${binary}" ] || return 1
  reported="$("${binary}" version 2>&1 || "${binary}" --version 2>&1 || true)"
  case "${reported}" in
    *"${want#v}"*) return 0 ;;
  esac
  return 1
}

main() {
  local tool="${1-}" version="${2-}" dest="${3-}" os arch tmp want
  [ -n "${tool}" ] && [ -n "${version}" ] && [ -n "${dest}" ] || usage

  require_no_newline tool "${tool}"
  require_no_newline version "${version}"
  case "${version}" in
    v[0-9]*) ;;
    *) die "version must look like vMAJOR.MINOR.PATCH, got '${version}'" ;;
  esac

  os="$(host_os)"
  arch="$(host_arch)"
  describe_tool "${tool}" "${version}" "${os}" "${arch}"

  mkdir -p "${dest}"
  dest="$(cd -- "${dest}" && pwd)"

  if installed_version_matches "${dest}/${BINARY}" "${version}"; then
    log "${tool} ${version} already installed at ${dest}/${BINARY}"
    return 0
  fi

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/install-tool.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}'" EXIT

  fetch "${BASE_URL}/${MANIFEST}" "${tmp}/${MANIFEST}" ||
    die "could not download the checksum manifest ${BASE_URL}/${MANIFEST}"
  want="$(sha256_from_manifest "${tmp}/${MANIFEST}" "${ARCHIVE}")"
  download_verified "${BASE_URL}/${ARCHIVE}" "${tmp}/${ARCHIVE}" "${want}"

  tar -xzf "${tmp}/${ARCHIVE}" -C "${tmp}" "${BINARY}" ||
    die "archive ${ARCHIVE} did not contain a '${BINARY}' binary"

  install -m 0755 "${tmp}/${BINARY}" "${dest}/${BINARY}"
  log "installed ${tool} ${version} -> ${dest}/${BINARY}"
}

# Only run when executed, so tests can source this file and exercise
# describe_tool directly without the network.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
