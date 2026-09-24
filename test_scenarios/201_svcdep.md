# 2.1. Service dependency (201_svcdep)

## Description

A valid `dependsOn` chain: every service is correct, so all of them must land — and
in the declared order, not at once. The chain is the one from catalog's `apps/kserve`:
cert-manager issues the webhook certificates, the CRDs have to exist before the
controller that owns instances of them.

```mermaid
flowchart LR
    A["cert-manager<br/>1.20.2"] --> B["kserve-crd<br/>v0.18.0"] --> C["kserve-resources<br/>v0.18.0"]

    classDef svc fill:#ede9fe,stroke:#7c3aed,color:#0b1220
    class A,B,C svc
```

The scenario asserts that each service reaches the cluster only once the one it
depends on is deployed, and that all three can then be removed again.

> [!NOTE]
> The copy of cert-manager sets `crds.enabled: false` and a `fullnameOverride`,
> because KCM runs its own cert-manager here and its helm release already owns the
> cert-manager CRDs. Self-management means the services land in a cluster that is
> not empty.

## Scenario steps

```mermaid
%%{init: {'flowchart': {'padding': 16, 'nodeSpacing': 40, 'rankSpacing': 45}}}%%
flowchart LR
    P1["1) Build environment"]

    subgraph P2["2) Deploy services"]
        direction TB
        D1["Install ServiceTemplates"] --> D2["Deploy MultiClusterService"]
    end

    P3["3) Upgrade services<br/>(skipped)"]

    subgraph P4["4) Clean up"]
        direction TB
        C1["Remove services"] --> C2["Remove k0s cluster"]
    end

    P1 --> P2 --> P3 --> P4

    classDef off fill:#d7dde5,stroke:#7c8a9c,color:#33415a
    classDef dep fill:#ede9fe,stroke:#7c3aed,color:#0b1220
    classDef out fill:#dcfce7,stroke:#16a34a,color:#0b1220

    class P1,P3 off
    class D1,D2 dep
    class C1,C2 out
```

Grey phases are not part of this scenario: the environment is built once and shared
by every scenario, and this one declares no `upgrade:` block, so nothing is upgraded.

**Install ServiceTemplates** — one per service, named after the chart and version:

- `cert-manager-1-20-2`
- `kserve-crd-0-18-0`
- `kserve-resources-0-18-0`

**Deploy MultiClusterService** — one MCS carrying the whole chain:

```yaml
spec:
  serviceSpec:
    provider:
      selfManagement: true          # deploy into the cluster KCM runs in
    services:
      - template: cert-manager-1-20-2
        name: cert-manager
      - template: kserve-crd-0-18-0
        name: kserve-crd
        dependsOn: [cert-manager]
      - template: kserve-resources-0-18-0
        name: kserve-resources
        dependsOn: [kserve-crd]
```

## Run it

```bash
SCENARIO=201_svcdep ./scripts/run_scenario.sh
```

> [!WARNING]
> CI currently skips the `4) Clean up: Remove services` step for this scenario —
> the teardown wedges on the MCS finalizer, because the chart owning the CRDs is
> uninstalled before the release still holding a CR of them
> ([kcm#3021](https://github.com/k0rdent/kcm/issues/3021)). Known to fail on
> KCM 1.11.0, fixed between v1.11.0 and v1.12.0-rc1.

Defined in [`201_svcdep.yaml`](201_svcdep.yaml).
