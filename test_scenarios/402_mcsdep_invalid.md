# 4.2. Broken MultiClusterService dependency (402_mcsdep_invalid)

## Tested steps

1. Install the ServiceTemplates and wait for each to report `valid`.
2. Create both MultiClusterServices in a single apply. `base` carries `cert-manager`
   with `replicaCount: -1`, which helm refuses, so it never becomes healthy;
   `dependent` carries `traefik` and `dependsOn: base`.
3. For 180s `dependent` must get no ServiceSet at all — not a late rollout, none. The
   whole window is sat out whatever happens, so a slow start cannot pass for a refusal.
4. Report the conditions `dependent` is left with.
5. Remove the services: MCSs, ServiceSets, helm releases and workloads all gone.

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
                T1["cert-manager-1-20-2"] ~~~ T2["traefik-41-2-0"]
            end

            subgraph D2["Deploy MultiClusterServices<br/>created together"]
                direction TB
                subgraph DMB["mcs-402-mcsdep-invalid-base"]
                    M1["cert-manager-1-20-2<br/>never healthy"]
                end

                subgraph DMD["mcs-402-mcsdep-invalid-dependent"]
                    M2["traefik-41-2-0<br/>no ServiceSet ever"]
                end

                %% dependsOn on the edge, not in the title: a two-line subgraph
                %% title overlaps the box below it.
                DMB -- "dependsOn" --> DMD
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

    class P1,P3,DMD,M2 off
    class D1,D2 purple
    class DMB,T1,T2 pink
    class M1 fail
    class C1,C2 green
    class W2 bare
```

Defined in [`402_mcsdep_invalid.yaml`](402_mcsdep_invalid.yaml).
