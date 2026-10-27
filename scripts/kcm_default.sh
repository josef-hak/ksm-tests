#!/usr/bin/env bash
set -euo pipefail

# The KCM build this repository tests by default: the variant marked
# `prCheck: true` in scripts/config/kcm-variants.yaml.
#
# One place names it. Everything that needs a default -- a manual workflow run,
# a pull request, a local ./scripts/deploy_k0rdent.sh -- reads it from here
# rather than carrying its own copy, so bumping the variant bumps all of them.
#
# Prints shell assignments, usable three ways:
#   eval "$(./scripts/kcm_default.sh)"            # locally
#   ./scripts/kcm_default.sh >> "$GITHUB_ENV"     # in CI
#   KCM=$(./scripts/kcm_default.sh --version)     # just the version

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

require_yq

VARIANTS="$CONFIG_DIR/kcm-variants.yaml"
[[ -f "$VARIANTS" ]] || die "No $VARIANTS"

sel='.variants[] | select(.prCheck == true)'
kcm="$(yq -r "$sel | .kcm // \"\"" "$VARIANTS")"
mode="$(yq -r "$sel | .mode // \"\"" "$VARIANTS")"
oci="$(yq -r "$sel | .oci // \"\"" "$VARIANTS")"

[[ -n "$kcm" ]] \
    || die "No variant in $VARIANTS has 'prCheck: true', so there is no default build."

if [[ "${1:-}" == "--version" ]]; then
    echo "$kcm"
    exit 0
fi

echo "KCM=$kcm"
echo "KCM_MODE=$mode"
# Only when the variant carries one; otherwise common.sh's own default applies.
[[ -n "$oci" ]] && echo "OCI_URL=$oci"
exit 0
