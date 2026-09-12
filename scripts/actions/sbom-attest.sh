#!/usr/bin/env bash
#
# Backs the SBOM half of .github/actions/sbom-attest.
#
#   IMAGE             full image name including registry, no tag or digest
#   PLATFORM_DIGESTS  {"linux/amd64":"sha256:...", ...}
#   SBOM_OUTPUT_DIR   where to write the generated documents
#
# Each SBOM is attested to the child manifest it describes, never to the index.
# A referrer descriptor carries only digest, mediaType, size, artifactType and
# annotations -- there is no name field -- so two CycloneDX documents parked on
# one index digest are indistinguishable in a referrers listing without pulling
# every payload. Attaching each to its own platform manifest also puts it where
# a consumer that resolved linux/amd64 will actually look.
#
# --new-bundle-format=true is passed explicitly rather than inherited from
# whatever the installed cosign defaults to. It is what publishes through the
# OCI referrers API instead of a legacy .att tag, and that has to be this
# repository's decision, not one that can move under us between cosign
# releases.

set -euo pipefail

# shellcheck source=scripts/actions/lib.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

main() {
  local image="${IMAGE-}" digests="${PLATFORM_DIGESTS-}" outdir="${SBOM_OUTPUT_DIR-}"
  local safe platform digest arch file

  require_set image "${image}"
  require_set platform_digests "${digests}"
  require_set sbom_output_dir "${outdir}"
  require_no_newline image "${image}"

  mkdir -p "${outdir}"

  # Flattened image path, safe as a filename and as an artifact name.
  safe="$(printf '%s' "${image}" | tr -c 'A-Za-z0-9._-' '-')"

  while IFS=$'\t' read -r platform digest; do
    [ -n "${platform}" ] || continue
    arch="$(printf '%s' "${platform}" | tr '/' '-')"
    file="${outdir}/sbom-${safe}-${arch}.cdx.json"

    # The child manifest digest is passed straight through, so syft scans
    # exactly one root filesystem and needs no --platform disambiguation.
    timeout --foreground 300s syft scan \
      "registry:${image}@${digest}" \
      --output "cyclonedx-json=${file}"

    "${REPO_ROOT}/scripts/validate-digests.sh" sbom "${file}"

    timeout --foreground 120s cosign attest \
      --yes \
      --new-bundle-format=true \
      --type cyclonedx \
      --predicate "${file}" \
      "${image}@${digest}"

    notice "attested CycloneDX SBOM for ${platform} to ${digest}"
    # Backticks are markdown for the job summary, not command substitution.
    # shellcheck disable=SC2016
    printf -- '- CycloneDX attested for `%s` at `%s`\n' "${platform}" "${digest}" \
      >>"${GITHUB_STEP_SUMMARY}"
  done <<<"$(printf '%s' "${digests}" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')"
}

main "$@"
