#!/usr/bin/env bash
#
# Backs .github/actions/resolve-digests.
#
# Resolves the index digest for a pushed tag and, for a multi-platform build,
# each per-platform child manifest digest.
#
#   IMAGE           full image name including registry, no tag or digest
#   TAG             tag to resolve, normally the candidate tag
#   PLATFORMS_JSON  [{"platform":..,"arch":..,"runner":..}, ...]
#
# `crane digest <ref>` returns the index digest, which is the right subject for
# provenance and the wrong one for an SBOM: an SBOM describes exactly one root
# filesystem, and a consumer that resolved linux/amd64 enumerates referrers on
# that child manifest, not on the index. `crane digest --platform` resolves the
# index to a child and errors when the platform is absent, so a release that
# silently lost an architecture fails here rather than shipping two SBOMs
# pinned to the same subject.

set -euo pipefail

# shellcheck source=scripts/actions/lib.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

main() {
  local image="${IMAGE-}" tag="${TAG-}" platforms="${PLATFORMS_JSON-}"
  local count expect_index index platform child digests mapping

  require_set image "${image}"
  require_set tag "${tag}"
  require_set platforms "${platforms}"
  require_no_newline image "${image}"
  require_no_newline tag "${tag}"

  count="$(printf '%s' "${platforms}" | jq 'length')"
  [ "${count}" -gt 0 ] || die "the platforms input is empty"

  if [ "${count}" -gt 1 ]; then
    expect_index=true
  else
    expect_index=false
  fi

  index="$(timeout --foreground 120s crane digest "${image}:${tag}")"

  digests=""
  mapping='{}'
  while IFS= read -r platform; do
    [ -n "${platform}" ] || continue
    if [ "${expect_index}" = "true" ]; then
      child="$(timeout --foreground 120s crane digest \
        --platform "${platform}" "${image}@${index}")"
    else
      # A single-platform build produces a plain manifest, so the child is the
      # reference itself. Going through the index path here would ask crane to
      # resolve a platform inside something that is not an index, which
      # succeeds by returning the same digest and would hide a genuinely
      # single-architecture image behind an apparently multi-platform result.
      child="${index}"
    fi
    digests="${digests} ${child}"
    mapping="$(printf '%s' "${mapping}" |
      jq --arg p "${platform}" --arg d "${child}" '. + {($p): $d}')"
  done <<<"$(printf '%s' "${platforms}" | jq -r '.[].platform')"

  # Word splitting is intended: digests is a space-separated list built above.
  # shellcheck disable=SC2086
  "${REPO_ROOT}/scripts/validate-digests.sh" digests "${expect_index}" "${index}" ${digests}

  emit_output index_digest "${index}"
  emit_output expect_index "${expect_index}"
  emit_output image_ref "${image}@${index}"
  emit_output platform_digests "$(printf '%s' "${mapping}" | jq -c .)"

  {
    printf '### Digests\n\n'
    printf '| Subject | Digest |\n|---|---|\n'
    # Backticks are markdown for the job summary, not command substitution.
    # shellcheck disable=SC2016
    printf '| index | `%s` |\n' "${index}"
    printf '%s' "${mapping}" | jq -r 'to_entries[] | "| \(.key) | `\(.value)` |"'
    printf '\n'
  } >>"${GITHUB_STEP_SUMMARY}"
}

main "$@"
