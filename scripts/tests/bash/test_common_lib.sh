#!/usr/bin/env bash
# Tests for scripts/lib/common.sh
# shellcheck source=scripts/tests/bash/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPTS_DIR/lib/common.sh"

# ── fqdn_version ─────────────────────────────────────────────────────────────
assert_eq "1.11.0 -> 1-11-0" "1-11-0" "$(fqdn_version 1.11.0)"
assert_eq "strips the v prefix" "1-11-0" "$(fqdn_version v1.11.0)"
assert_eq "handles pre-release suffixes" "1-11-0-rc1" "$(fqdn_version 1.11.0-rc1)"
assert_eq "single component" "2" "$(fqdn_version 2)"

# ── paths ────────────────────────────────────────────────────────────────────
assert_eq "PROJECT_ROOT points at the repo" "$REPO_ROOT" "$PROJECT_ROOT"
assert_eq "CONFIG_DIR is derived from it" "$REPO_ROOT/scripts/config" "$CONFIG_DIR"

# ── defaults ─────────────────────────────────────────────────────────────────
assert_eq "TEST_MODE defaults to self" "self" "$TEST_MODE"
# One cluster, so the checks read back through the same kubeconfig they wrote
# through. A second path here would mean a second cluster came back.
assert_eq "the child kubeconfig is the management one" "$KUBECONFIG_MGMT" "$KUBECONFIG_CHILD"
assert_contains "sveltos is enabled" "$KCM_PROVIDERS" "projectsveltos"
# Nothing is provisioned under self-management, so anything else here would
# just be a chart KCM reconciles for nothing.
assert_eq "sveltos is the whole provider list" "projectsveltos" "$KCM_PROVIDERS"
assert_eq "and no cluster template is needed" "" "$KCM_CLUSTER_TEMPLATES"

# Adopted mode is the same environment plus a second cluster: the checks have
# to read back through that one, and the ClusterTemplate it is built from has
# to be installed. The unsets are because sourcing the library above exported
# the self-management answers -- a child shell would inherit them.
adopted="$(env -u KUBECONFIG_CHILD -u KCM_CLUSTER_TEMPLATES TEST_MODE=adopted bash -c \
    "source '$SCRIPTS_DIR/lib/common.sh'; echo \"\$KUBECONFIG_CHILD \$KCM_PROVIDERS \$KCM_CLUSTER_TEMPLATES\"")"
assert_eq "adopted mode targets the adopted cluster, on sveltos alone" \
    "$KUBECONFIG_ADOPTED projectsveltos adopted-cluster" "$adopted"
# ── KSM_PROVIDER ─────────────────────────────────────────────────────────────
# Picking Argo CD has to move three things together, or the run installs one
# engine and asks another to deploy. The unsets are for the same reason as
# above: sourcing the library exported the Sveltos answers.
argo="$(env -u KCM_PROVIDERS -u KCM_ENABLE_ARGOCD_CTRL -u KCM_ENABLE_SVELTOS_CTRL \
    KSM_PROVIDER=ksm-argocd bash -c \
    "source '$SCRIPTS_DIR/lib/common.sh'; echo \"\$KCM_PROVIDERS \$KCM_ENABLE_ARGOCD_CTRL \$KCM_ENABLE_SVELTOS_CTRL\"")"
assert_eq "argocd is the whole provider list, with its adapter on and sveltos off" \
    "argocd true false" "$argo"

# An adopted cluster is a SveltosCluster whoever deploys to it, so the Sveltos
# CRDs stay even when Argo CD does the deploying.
argo_adopted="$(env -u KCM_PROVIDERS TEST_MODE=adopted KSM_PROVIDER=ksm-argocd bash -c \
    "source '$SCRIPTS_DIR/lib/common.sh'; echo \"\$KCM_PROVIDERS\"")"
assert_eq "adopted mode on argocd keeps sveltos for the SveltosCluster" \
    "projectsveltos argocd" "$argo_adopted"

# The pods waited for and the logs collected follow the engine that is
# installed, so a run on Argo CD looks at the argocd namespace and not at one
# that was never created.
assert_eq "sveltos runs in its own namespace" "projectsveltos" "$KSM_NAMESPACES"
assert_eq "argocd replaces it, not adds to it" "argocd" \
    "$(env -u KCM_PROVIDERS -u KSM_NAMESPACES KSM_PROVIDER=ksm-argocd bash -c \
        "source '$SCRIPTS_DIR/lib/common.sh'; echo \"\$KSM_NAMESPACES\"")"
assert_eq "adopted mode on argocd has both" "projectsveltos argocd" \
    "$(env -u KCM_PROVIDERS -u KSM_NAMESPACES TEST_MODE=adopted KSM_PROVIDER=ksm-argocd bash -c \
        "source '$SCRIPTS_DIR/lib/common.sh'; echo \"\$KSM_NAMESPACES\"")"

# Flux is a subchart of KCM, not a provider chart, so it moves the adapter
# switches without adding anything to the Management -- and under
# self-management that leaves no provider at all, which is the point: nothing
# there is a SveltosCluster.
flux="$(env -u KCM_PROVIDERS -u KCM_ENABLE_ARGOCD_CTRL -u KCM_ENABLE_SVELTOS_CTRL -u KCM_ENABLE_FLUX_CTRL \
    KSM_PROVIDER=flux bash -c \
    "source '$SCRIPTS_DIR/lib/common.sh'; echo \"[\$KCM_PROVIDERS] \$KCM_ENABLE_FLUX_CTRL \$KCM_ENABLE_SVELTOS_CTRL\"")"
assert_eq "flux enables no provider, with its adapter on and sveltos off" \
    "[] true false" "$flux"
assert_eq "and has no namespace of its own to wait for" "" \
    "$(env -u KCM_PROVIDERS -u KSM_NAMESPACES KSM_PROVIDER=flux bash -c \
        "source '$SCRIPTS_DIR/lib/common.sh'; echo \"\$KSM_NAMESPACES\"")"

# The short name is what a run and a CI job are tagged with; the provider name
# is what the manifests carry. A caller that already names the provider keeps
# working.
for pair in "sveltos ksm-projectsveltos" "argo ksm-argocd" "flux ksm-flux" \
            "ksm-projectsveltos ksm-projectsveltos" "ksm-argocd ksm-argocd" "ksm-flux ksm-flux"; do
    read -r given want <<< "$pair"
    got="$(env KSM_PROVIDER="$given" bash -c \
        "source '$SCRIPTS_DIR/lib/common.sh'; echo \"\$KSM_PROVIDER_NAME\"")"
    assert_eq "KSM_PROVIDER=$given names $want" "$want" "$got"
done

if env KSM_PROVIDER=nope bash -c "source '$SCRIPTS_DIR/lib/common.sh'" >/dev/null 2>&1; then
    assert_eq "an unknown adapter is refused" "rejected" "accepted"
else
    assert_eq "an unknown adapter is refused" "rejected" "rejected"
fi

assert_not_contains "aws provider is off" "$KCM_PROVIDERS" "cluster-api-provider-aws"
assert_not_contains "azure provider is off" "$KCM_PROVIDERS" "cluster-api-provider-azure"
# Only source mode uses the local registry; release mode pulls from the URL.
assert_eq "registry URL matches the registry name" "oci://$REGISTRY_NAME:5000/charts" \
    "$(KCM_MODE=source bash -c \
        "unset TEMPLATES_REPO_URL; source '$SCRIPTS_DIR/lib/common.sh'; echo \$TEMPLATES_REPO_URL")"

# ── chart helpers ────────────────────────────────────────────────────────────
tmpchart="$(mktemp -d)/mychart"
mkdir -p "$tmpchart"
cat > "$tmpchart/Chart.yaml" <<'EOF'
apiVersion: v2
name: adopted-cluster
description: |
  version: 9.9.9 should not be picked up from an indented line
type: application
version: 1.0.2
appVersion: "v1.36.1+k0s.0"
EOF
assert_eq "chart_name reads name" "adopted-cluster" "$(chart_name "$tmpchart")"
assert_eq "chart_version reads version" "1.0.2" "$(chart_version "$tmpchart")"
assert_eq "template_name combines both" "adopted-cluster-1-0-2" "$(template_name "$tmpchart")"
rm -rf "$(dirname "$tmpchart")"

# ── require_env ──────────────────────────────────────────────────────────────
out=$(SOME_VAR="" bash -c "source '$SCRIPTS_DIR/lib/common.sh'; require_env SOME_VAR" 2>&1)
assert_eq "require_env fails on an unset var" 1 "$?"
assert_contains "names the missing var" "$out" "SOME_VAR"

SOME_VAR="a value" bash -c "source '$SCRIPTS_DIR/lib/common.sh'; require_env SOME_VAR" >/dev/null 2>&1
assert_eq "require_env passes when set" 0 "$?"

# ── require_cmd ──────────────────────────────────────────────────────────────
out=$(bash -c "source '$SCRIPTS_DIR/lib/common.sh'; require_cmd definitely-not-a-real-binary" 2>&1)
assert_eq "require_cmd fails on a missing binary" 1 "$?"
assert_contains "suggests deps.sh" "$out" "deps.sh"

finish
