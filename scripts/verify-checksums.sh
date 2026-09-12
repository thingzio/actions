#!/usr/bin/env bash
#
# Verifies that a checksum file describes exactly the artifacts it is about to
# be signed for.
#
#   scripts/verify-checksums.sh <checksums-file> <assets-directory>
#
# release-go.yaml signs checksums.txt and attests it with subject-checksums,
# which makes every (digest, filename) pair in that file a subject of the
# provenance -- attested under the reusable workflow's identity, not the
# caller's. The file itself is produced by the build job, which by design runs
# the caller's goreleaser hooks. Treating it as trustworthy because it contains
# digests confuses committing to bytes with having produced them.
#
# So the trusted job re-derives the digests from the artifacts actually attached
# to the release and requires them to agree. Three things are rejected:
#
#   * an empty or entry-less file. `sha256sum --check` exits 0 on empty input,
#     so without this a release could be signed and attested while committing
#     to nothing at all.
#
#   * a line naming an artifact that is not on the release. That is a subject
#     the provenance would vouch for without the build ever producing it.
#
#   * a digest that does not match the artifact bytes.
#
# What this does NOT do is claim the artifacts are good. A compromised build
# produces bad binaries and honest provenance describing them; that is what
# SLSA promises and what it does not. This closes the narrower gap: every
# subject named is an artifact this release actually carries.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

usage() {
  printf 'usage: %s <checksums-file> <assets-directory>\n' "${0##*/}" >&2
  exit 2
}

main() {
  local checksums="${1-}" assets="${2-}" entries digest name line got

  [ -n "${checksums}" ] && [ -n "${assets}" ] || usage
  [ -r "${checksums}" ] || die "cannot read checksum file '${checksums}'"
  [ -d "${assets}" ] || die "cannot read assets directory '${assets}'"

  entries=0
  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      "") continue ;;
    esac

    # The sha256sum format: 64 hex digits, two spaces (or space and "*" for
    # binary mode), then the name. Anything else is rejected rather than
    # skipped -- a line this cannot parse is a subject nobody checked.
    digest="${line%%[ ]*}"
    name="${line#* }"
    name="${name# }"
    name="${name#\*}"

    case "${digest}" in
      *[!0-9a-fA-F]* | "") die "checksum file has a malformed line: ${line}" ;;
    esac
    [ "${#digest}" = "64" ] || die "checksum file has a non-sha256 digest: ${line}"
    [ -n "${name}" ] || die "checksum file has a line with no filename: ${line}"

    # A name that escapes the assets directory would let a line point the check
    # at a file the release does not carry.
    case "${name}" in
      /* | *..*) die "checksum file names a path outside the release: ${name}" ;;
    esac

    [ -f "${assets}/${name}" ] ||
      die "checksum file names '${name}', which is not attached to this release; provenance would claim a subject the build never produced"

    # sha256_of rather than `sha256sum --check`, which does not exist on macOS:
    # the same script has to give the same answer on a laptop and on a runner.
    got="$(sha256_of "${assets}/${name}" | tr '[:upper:]' '[:lower:]')"
    if [ "${got}" != "$(printf '%s' "${digest}" | tr '[:upper:]' '[:lower:]')" ]; then
      die "'${name}' on the release does not match its digest in the checksum file"
    fi

    entries=$((entries + 1))
  done < "${checksums}"

  [ "${entries}" -gt 0 ] ||
    die "checksum file has no entries; signing it would commit to nothing"

  printf 'verified %s artifact(s) against %s\n' "${entries}" "${assets}"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
