#!/usr/bin/env bash
# Tests the Management manifest apply_management.sh renders.
# shellcheck source=scripts/tests/bash/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

setup_mock_bin
write_mock kubectl <<'EOF'
#!/bin/bash
exit 0
EOF

ENVDIR="$(mktemp -d)"
# BIN_DIR normally lives outside it; keep pointing at the real tools.
BIN_DIR="$REPO_ROOT/.bin"
export ENVDIR BIN_DIR
echo 'RELEASE_NAME=kcm-1-11-0' > "$ENVDIR/release.env"
cat > "$ENVDIR/kcm-values.rendered.yaml" <<'EOF'
image:
  repository: localhost/kcm/controller
  tag: latest
controller:
  createManagement: false
EOF

KCM_PROVIDERS="cluster-api-provider-docker projectsveltos" \
    bash "$SCRIPTS_DIR/steps/apply_management.sh" >/dev/null 2>&1
assert_eq "renders and applies successfully" 0 "$?"

rendered="$(cat "$ENVDIR/management.rendered.yaml")"
assert_contains "references the Release from release.env" "$rendered" "release: kcm-1-11-0"
assert_contains "lists the docker provider" "$rendered" "- name: cluster-api-provider-docker"
assert_contains "lists sveltos" "$rendered" "- name: projectsveltos"
assert_not_contains "does not enable aws" "$rendered" "cluster-api-provider-aws"
assert_eq "exactly 2 providers" 2 "$(grep -cE '^ +- name:' <<< "$rendered")"
# Without this the HelmRelease would reinstall KCM from the published image.
assert_contains "carries the local image into core.kcm.config" "$rendered" "localhost/kcm/controller"

# The sveltos values file is comments only by default, and a config block with
# nothing in it is not the same as no config block: KCM would read it as "no
# values" and the chart's defaults would apply anyway, but the manifest would
# claim a customisation that is not there.
yq -e '.spec.providers[] | select(.name == "projectsveltos") | has("config")' \
    "$ENVDIR/management.rendered.yaml" >/dev/null 2>&1
assert_eq "no config block for an empty values file" 1 "$?"

SVELTOS_VALUES_FILE="$ENVDIR/sveltos-values.yaml"
cat > "$SVELTOS_VALUES_FILE" <<'EOF'
techsupportController:
  enabled: false
EOF
KCM_PROVIDERS="cluster-api-provider-docker projectsveltos"     SVELTOS_VALUES="$SVELTOS_VALUES_FILE" SVELTOS_AGENT_MGMT=true     bash "$SCRIPTS_DIR/steps/apply_management.sh" >/dev/null 2>&1
rendered="$(cat "$ENVDIR/management.rendered.yaml")"
assert_eq "still exactly 2 providers" 2 "$(grep -cE '^ +- name:' <<< "$rendered")"
assert_eq "carries the sveltos values" "false" \
    "$(yq -r '.spec.providers[] | select(.name == "projectsveltos")
              | .config.techsupportController.enabled' "$ENVDIR/management.rendered.yaml")"
assert_eq "and the agent switch on top of them" "true" \
    "$(yq -r '.spec.providers[] | select(.name == "projectsveltos")
              | .config.agent.managementCluster' "$ENVDIR/management.rendered.yaml")"
# The config belongs to sveltos alone; on the docker provider the chart would
# reject it as unknown values.
assert_eq "and nothing else gets one" "null" \
    "$(yq -r '.spec.providers[] | select(.name == "cluster-api-provider-docker")
              | .config' "$ENVDIR/management.rendered.yaml")"

# Missing inputs must fail loudly rather than render junk.
rm -f "$ENVDIR/kcm-values.rendered.yaml"
out=$(bash "$SCRIPTS_DIR/steps/apply_management.sh" 2>&1)
assert_eq "fails without the rendered values" 1 "$?"
assert_contains "points at deploy_kcm.sh" "$out" "deploy_kcm.sh"

rm -f "$ENVDIR/release.env"
out=$(bash "$SCRIPTS_DIR/steps/apply_management.sh" 2>&1)
assert_eq "fails without release.env" 1 "$?"
assert_contains "points at apply_release.sh" "$out" "apply_release.sh"

rm -rf "$ENVDIR" "$MOCK_BIN"
finish
