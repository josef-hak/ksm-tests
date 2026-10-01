# 2.2. Invalid service in a dependency chain (202_svcdep_invalid)

## Tested steps

1. Install the ServiceTemplates and wait for each to report `valid`.
2. Deploy one MultiClusterService carrying `traefik → cert-manager → kserve-crd`.
   `cert-manager` asks for `replicaCount: -1`, which helm refuses — invalid values
   rather than a missing image, because a bad image still yields a successful release
   and the chain would simply carry on.
3. `cert-manager` is stamped `Failed` in the ServiceSet, and the ServiceSet itself must
   not report `deployed` while one of its services is failed.
4. For 120s `kserve-crd` stays uninstalled: never `Deployed`, and no workloads left in
   its namespace. Long enough to tell blocked from merely slow. KCM reports a blocked
   service by leaving it out of the status, not by listing it as pending.
5. `traefik` was deployed before the failure and has to survive it — `Deployed`, with
   its workloads still there. A moment of `Provisioning` is a re-reconcile and is
   tolerated; `Failed` is a rollback and is not.
6. Remove the services: MCS, ServiceSet, helm releases and workloads all gone.

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

            subgraph D2["Deploy MultiClusterService"]
                subgraph DM["mcs-202-svcdep-invalid"]
                    direction TB
                    M1["traefik-41-2-0<br/>kept"] --> M2["cert-manager-1-20-2<br/>failed"] --> M3["kserve-crd-0-18-0<br/>never installed"]
                end
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
    classDef purple fill:#ede9fe,stroke:#7c3aed,color:#0b1220
    classDef pink fill:#fce7f3,stroke:#db2777,color:#0b1220
    classDef fail fill:#fee2e2,stroke:#dc2626,color:#0b1220
    classDef green fill:#dcfce7,stroke:#16a34a,color:#0b1220
    classDef bare fill:none,stroke:none

    class P1,P3,M3 off
    class D1,D2 purple
    class DM,T1,T2,T3,M1 pink
    class M2 fail
    class C1,C2 green
    class W2 bare
```

Defined in [`202_svcdep_invalid.yaml`](202_svcdep_invalid.yaml).
