# 3.2. Failed atomic upgrade (302_upgrade_invalid_atomic)

## Tested steps

1. Install the ServiceTemplates and wait for each to report `valid`.
2. Deploy one MultiClusterService carrying `traefik → cert-manager → kserve-crd` with
   `helmOptions.atomic` set from the first deploy — adding it at upgrade time makes
   sveltos reinstall rather than upgrade.
3. Record the state everything later is judged against: helm revision, chart version
   and pod UIDs per service.
4. Upgrade `cert-manager` to 1.21.1 with `replicaCount: -1` on top, so it is the
   upgrade that fails. Unlike [`202_svcdep_invalid`](202_svcdep_invalid.md) there is a
   previous healthy state to return to.
5. Wait for the release to settle back on chart `1.20.2`, `deployed`, at a higher
   revision than before. Helm reports `failed` briefly on the way, so only a sustained
   reading decides: 90s on a failed release, or 90s with no release at all, and the
   scenario fails — removed instead of rolled back is its own verdict.
6. `cert-manager` pods ready again: a rollback that leaves nothing running is not one.
7. `traefik` and `kserve-crd` — same chart version, same pod UIDs.
8. Remove the services: MCS, ServiceSet, helm releases and workloads all gone.

## Scenario schema

```mermaid
%%{init: {'flowchart': {'padding': 10, 'nodeSpacing': 18, 'rankSpacing': 28, 'subGraphTitleMargin': {'top': 6, 'bottom': 10}}}}%%
flowchart LR
    P1["1) Build environment"]

    subgraph P2["2) Deploy services"]
        subgraph W2[" "]
            direction LR
            subgraph D1["Install ServiceTemplates"]
                direction TB
                T1["traefik-41-2-0"] ~~~ T2["cert-manager-1-20-2"] ~~~ T3["kserve-crd-0-18-0"]
            end

            subgraph D2["Deploy MultiClusterService<br/>helmOptions.atomic"]
                direction TB
                M1["traefik"] --> M2["cert-manager 1.20.2"] --> M3["kserve-crd"]
            end

            D1 --> D2
        end
    end

    subgraph P3["3) Upgrade services"]
        subgraph W3[" "]
            direction LR
            subgraph U1["Direct upgrade"]
                direction TB
                S1["cert-manager → 1.21.1<br/>replicaCount: -1<br/>refused by helm"] --> S2["atomic undoes it<br/>back on 1.20.2, healthy"]
                S3["traefik<br/>kserve-crd<br/>untouched"]
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
    classDef fail fill:#fee2e2,stroke:#dc2626,color:#0b1220
    classDef green fill:#dcfce7,stroke:#16a34a,color:#0b1220
    classDef bare fill:none,stroke:none

    class P1,U2,S3 off
    class D1,D2,T1,T2,T3,M1,M2,M3 pink
    class U1,S2 amber
    class S1 fail
    class C1,C2 green
    class W2,W3 bare
```

Defined in [`302_upgrade_invalid_atomic.yaml`](302_upgrade_invalid_atomic.yaml).
