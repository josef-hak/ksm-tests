# 3.1. Upgrade one service of a chain (301_upgrade)

## Tested steps

1. Install the ServiceTemplates and wait for each to report `valid`.
2. Deploy one MultiClusterService carrying `traefik → cert-manager → kserve-crd`, pods
   ready where declared.
3. Record the state everything later is judged against: helm revision, chart version
   and pod UIDs per service.
4. Install the ServiceTemplate for `cert-manager` 1.21.1 and patch the MCS to it.
   `cert-manager` sits in the middle, so both directions are checked at once.
5. `cert-manager` — the ServiceSet says `Deployed` and the helm release is on chart
   `1.21.1`, `deployed`. The status matters as much as the version: helm stamps the new
   revision as soon as the upgrade starts.
6. `traefik` and `kserve-crd` — same chart version and the very same pod UIDs. A moved
   helm revision with unchanged pods is only warned about, replaced pods are a failure.
7. Remove the services: MCS, ServiceSet, helm releases and workloads all gone.

## Scenario schema

```mermaid
%%{init: {'flowchart': {'padding': 10, 'nodeSpacing': 18, 'rankSpacing': 28, 'subGraphTitleMargin': {'top': 6, 'bottom': 10}}}}%%
flowchart TB
    P1["1) Build environment"]

    subgraph P2["2) Deploy services"]
        subgraph W2[" "]
            direction LR
            subgraph D1["Install ServiceTemplates"]
                direction TB
                T1["traefik-41-2-0"] ~~~ T2["cert-manager-1-20-2"] ~~~ T3["kserve-crd-0-18-0"]
            end

            subgraph D2["Deploy MultiClusterService"]
                direction TB
                M1["traefik"] --> M2["cert-manager 1.20.2"] --> M3["kserve-crd"]
            end

            D1 --> D2
        end
    end

    subgraph P3["3) Upgrade services"]
        subgraph W3[" "]
            direction LR
            subgraph U1["Upgrade MultiClusterService services"]
                direction TB
                V1["traefik"] --> V2["cert-manager 1.20.2"] --> V3["kserve-crd"]
                V2 --> V4["cert-manager 1.21.1"]
            end

            U2["Upgrade via ServiceTemplateChain<br/>(skipped)"]
        end
    end

    subgraph P4["4) Clean up"]
        C1["Remove services"] --> C2["Remove k0s cluster"]
    end

    P1 --> P2 --> P3 --> P4

    classDef off fill:#d7dde5,stroke:#7c8a9c,color:#33415a
    classDef pink fill:#fce7f3,stroke:#db2777,color:#0b1220
    classDef amber fill:#fef3c7,stroke:#d97706,color:#0b1220
    classDef green fill:#dcfce7,stroke:#16a34a,color:#0b1220
    classDef bare fill:none,stroke:none

    class P1,U2,V1,V3 off
    class D1,D2,T1,T2,T3,M1,M2,M3 pink
    class U1,V2,V4 amber
    class C1,C2 green
    class W2,W3 bare
```

Defined in [`301_upgrade.yaml`](301_upgrade.yaml).
