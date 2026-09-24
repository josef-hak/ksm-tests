# 2.1. Service dependency (201_svcdep)

## Tested steps

1. Install the ServiceTemplates and wait for each to report `valid`.
2. Deploy one MultiClusterService carrying the whole chain.
3. `cert-manager` — deployed helm release, pods ready.
4. `kserve-crd` — deployed helm release; CRDs only, no pods to wait for.
5. `kserve-resources` — deployed helm release, controller pods ready.
6. The MCS reports `ClusterInReadyState`.
7. Remove the services: MCS, ServiceSet, helm releases and workloads all gone.

## Scenario steps

```mermaid
%%{init: {'flowchart': {'padding': 10, 'nodeSpacing': 18, 'rankSpacing': 28}}}%%
flowchart LR
    P1["1) Build environment"]

    subgraph P2["2) Deploy services"]
        subgraph W2[" "]
            direction LR
            subgraph D1["Install ServiceTemplates"]
                direction TB
                T1["cert-manager-1-20-2"] ~~~ T2["kserve-crd-0-18-0"] ~~~ T3["kserve-resources-0-18-0"]
            end

            subgraph D2["Deploy MultiClusterService"]
                direction TB
                M1["cert-manager"] --> M2["kserve-crd"] --> M3["kserve-resources"]
            end

            D1 --> D2
        end
    end

    P3["3) Upgrade services<br/>(skipped)"]

    subgraph P4["4) Clean up"]
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

> [!WARNING]
> CI currently skips the `4) Clean up: Remove services` step for this scenario —
> the teardown wedges on the MCS finalizer, because the chart owning the CRDs is
> uninstalled before the release still holding a CR of them
> ([kcm#3021](https://github.com/k0rdent/kcm/issues/3021)).

Defined in [`201_svcdep.yaml`](201_svcdep.yaml).
