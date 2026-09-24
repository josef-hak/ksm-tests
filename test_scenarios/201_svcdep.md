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
%%{init: {'themeVariables': {'fontFamily': 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace', 'fontSize': '13px'}, 'flowchart': {'padding': 10, 'nodeSpacing': 18, 'rankSpacing': 28}}}%%
flowchart LR
    P1["1) Build environment"]

    subgraph P2["2) Deploy services"]
        subgraph W2[" "]
            direction TB
            subgraph D1["Install ServiceTemplates"]
                direction LR
                T1["cert-manager-1-20-2"] ~~~ T2["kserve-crd-0-18-0"] ~~~ T3["kserve-resources-0-18-0"]
            end

            subgraph D2["Deploy MultiClusterService"]
                direction LR
                M1["cert-manager"] --> M2["kserve-crd"] --> M3["kserve-resources"]
            end

            D1 --> D2
        end
    end

    P3["3) Upgrade services<br/>(skipped)"]

    subgraph P4["4) Clean up"]
        direction LR
        C1["Remove services"] --> C2["Remove k0s cluster"]
    end

    P1 --> P2 --> P3 --> P4

    classDef off fill:#d7dde5,stroke:#7c8a9c,color:#33415a
    classDef pink fill:#fce7f3,stroke:#db2777,color:#0b1220
    classDef green fill:#dcfce7,stroke:#16a34a,color:#0b1220
    classDef bare fill:none,stroke:none

    class P1,P3 off
    class D1,D2,T1,T2,T3,M1,M2,M3 pink
    class C1,C2 green
    class W2 bare
```

Grey phases are not part of this scenario: the environment is built once and shared
by every scenario, and this one declares no `upgrade:` block, so nothing is upgraded.

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
