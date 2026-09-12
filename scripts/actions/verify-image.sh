#!/usr/bin/env bash
#
# Backs .github/actions/verify-image. This is the consumer-facing verification
# contract expressed as code, so the commands published in the README are proven
# on every pull request instead of documented and left to rot.
#
#   scripts/actions/verify-image.sh provenance
#   scripts/actions/verify-image.sh sbom
#
#   IMAGE_REF         <image>@<digest>, must be digest-pinned
#   REPO              owner/repo that owns the attestation (the caller)
#   SIGNER_REPO       owner/repo containing the reusable workflow that signed
#   SIGNER_WORKFLOW   path of the reusable workflow that signed
#   PLATFORM_DIGESTS  {"linux/amd64":"sha256:...", ...}   (sbom mode)
#
# The split between REPO and SIGNER_REPO is the entire point. The attestation is
# stored against the caller's repository but signed by the build definition, so
# a consumer cannot mint provenance claiming this builder produced their image.

set -euo pipefail

# shellcheck source=scripts/actions/lib.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  printf 'usage: %s <provenance|sbom>\n' "${0##*/}" >&2
  exit 2
}

require_digest_pinned() {
  require_set image_ref "${IMAGE_REF-}"
  require_no_newline image_ref "${IMAGE_REF}"
  case "${IMAGE_REF}" in
    *@sha256:*) ;;
    *) die "image_ref must be pinned to a digest, got '${IMAGE_REF}'" ;;
  esac
}

verify_provenance() {
  local signer

  require_digest_pinned
  require_set signer_repo "${SIGNER_REPO-}"
  require_set signer_workflow "${SIGNER_WORKFLOW-}"
  require_no_newline signer_repo "${SIGNER_REPO}"
  require_no_newline signer_workflow "${SIGNER_WORKFLOW}"

  # --signer-repo and --signer-workflow are mutually exclusive: gh rejects the
  # combination with "if any flags in the group [...] are set none of the
  # others can be". --signer-workflow takes [host/]<owner>/<repo>/<path>, so it
  # already carries the repository and is the stricter of the two -- it pins
  # the exact build definition rather than only the repository that holds it.
  # The two inputs stay separate on the action for readability and are joined
  # here.
  signer="${SIGNER_REPO}/${SIGNER_WORKFLOW}"

  gh attestation verify "oci://${IMAGE_REF}" \
    --repo "${REPO}" \
    --signer-workflow "${signer}"

  notice "provenance verified for ${IMAGE_REF} (signed by ${signer})"
}

verify_sbom() {
  local image identity signer_escaped workflow_escaped platform digest

  require_digest_pinned
  require_set signer_workflow "${SIGNER_WORKFLOW-}"
  require_set platform_digests "${PLATFORM_DIGESTS-}"

  image="${IMAGE_REF%@*}"

  # The certificate identity is the reusable workflow's job_workflow_ref, which
  # Fulcio records as the Build Signer URI (OID 1.3.6.1.4.1.57264.1.9) and as
  # the certificate SAN. Anchored at the start and left open at the "@" so it
  # matches both a @refs/tags/vX.Y.Z pin and a @<sha> pin, and regexp
  # metacharacters in the caller-supplied path are escaped so a workflow
  # filename cannot widen the match.
  # The sed expression is a literal regexp character class; nothing in it is
  # meant to expand.
  # shellcheck disable=SC2016
  signer_escaped="$(printf '%s' "${SIGNER_REPO}" | sed 's/[.[\*^$()+?{|]/\\&/g')"
  # shellcheck disable=SC2016
  workflow_escaped="$(printf '%s' "${SIGNER_WORKFLOW}" | sed 's/[.[\*^$()+?{|]/\\&/g')"
  identity="^https://github\.com/${signer_escaped}/${workflow_escaped}@"

  while IFS=$'\t' read -r platform digest; do
    [ -n "${platform}" ] || continue
    timeout --foreground 120s cosign verify-attestation \
      --type cyclonedx \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      --certificate-identity-regexp "${identity}" \
      --certificate-github-workflow-repository "${REPO}" \
      "${image}@${digest}" >/dev/null

    notice "CycloneDX attestation verified for ${platform} (${digest})"
  done <<<"$(printf '%s' "${PLATFORM_DIGESTS}" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')"
}

main() {
  case "${1-}" in
    provenance) verify_provenance ;;
    sbom) verify_sbom ;;
    *) usage ;;
  esac
}

main "$@"
