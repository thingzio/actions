#!/usr/bin/env bash
#
# Backs the validation step of .github/actions/registry-login.
#
#   REGISTRY  registry host, optionally with a port
#
# Checked before the login action sees it so a malformed host fails with an
# actionable message instead of a docker CLI error, and so a newline can never
# reach the credential helper.

set -euo pipefail

# shellcheck source=scripts/actions/lib.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

main() {
  local registry="${REGISTRY-}"
  require_set registry "${registry}"
  require_no_newline registry "${registry}"
  [[ "${registry}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$ ]] ||
    die "registry '${registry}' is not a valid host[:port]"
}

main "$@"
