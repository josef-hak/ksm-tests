# 4.1. Dependent MultiClusterService (401_mcsdep_valid)

## Tested steps

1. Install the ServiceTemplates and wait for each to report `valid`.
2. Create both MultiClusterServices in a single apply — `base` with `cert-manager`,
   `dependent` with `traefik` and `dependsOn: base`. One apply on purpose: creation
   order must not be what sequences them, only `spec.dependsOn`.
3. Record when each MCS first gets a ServiceSet and when it first reports every service
   deployed.
4. `dependent` must not get its ServiceSet before `base` reported deployed — moment
   compared against moment, so a fast `base` cannot make this pass by accident.
5. Both end up deployed: helm releases `deployed` in the child cluster, pods ready.
6. Remove the services: MCSs, ServiceSets, helm releases and workloads all gone.

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
                subgraph DMB["mcs-401-mcsdep-valid-base"]
                    M1["cert-manager-1-20-2"]
                end

                subgraph DMD["mcs-401-mcsdep-valid-dependent"]
                    M2["traefik-41-2-0"]
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
    classDef green fill:#dcfce7,stroke:#16a34a,color:#0b1220
    classDef bare fill:none,stroke:none

    class P1,P3 off
    class D1,D2 purple
    class DMB,DMD,T1,T2,M1,M2 pink
    class C1,C2 green
    class W2 bare
```

Defined in [`401_mcsdep_valid.yaml`](401_mcsdep_valid.yaml).
