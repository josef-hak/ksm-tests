# 4.3. Dependency graph, not a chain (403_mcsdep_diamond)

## Tested steps

1. Install the ServiceTemplates and wait for each to report `valid`.
2. Create all four MultiClusterServices in a single apply — `certs` with `cert-manager`,
   `crds` and `proxy` both with `dependsOn: certs`, and `workload` with
   `dependsOn: [crds, proxy]`. One apply on purpose: creation order must not be what
   sequences them, only `spec.dependsOn`.
3. Record when each MCS first gets a ServiceSet and when it first reports every service
   deployed.
4. `crds` and `proxy` must not get their ServiceSets before `certs` reported deployed —
   the fan-out. Neither of them depends on the other, so nothing orders them between
   themselves.
5. `workload` must not get its ServiceSet before **both** `crds` and `proxy` reported
   deployed — the fan-in, and the thing a single-edge scenario cannot show. Each moment
   is compared against each dependency's, so finishing after the faster one is not
   enough.
6. All four end up deployed: helm releases `deployed` in the child cluster, pods ready.
7. Remove the services: MCSs, ServiceSets, helm releases and workloads all gone.

The services are the kserve stack split across the graph, so a leaking gate does not
merely lose a timing comparison: `kserve-resources` renders a Certificate and a
`ClusterStorageContainer`, and installing it before `cert-manager` and the kserve CRDs
are really there fails the helm release outright. `proxy` is the opposite case — traefik
needs nothing from `cert-manager`, so it is held back by the MCS edge alone.

Teardown runs from the last declared MultiClusterService backwards, which removes
`workload` before `crds`. The other order is the known teardown failure described in
[`201_svcdep.yaml`](201_svcdep.yaml).

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
                T1["cert-manager-1-20-2"] ~~~ T2["kserve-crd-0-18-0"] ~~~ T3["traefik-41-2-0"] ~~~ T4["kserve-resources-0-18-0"]
            end

            subgraph D2["Deploy MultiClusterServices<br/>created together"]
                direction TB
                subgraph DMC["mcs-403-mcsdep-diamond-certs"]
                    M1["cert-manager-1-20-2"]
                end

                subgraph DMR["mcs-403-mcsdep-diamond-crds"]
                    M2["kserve-crd-0-18-0"]
                end

                subgraph DMP["mcs-403-mcsdep-diamond-proxy"]
                    M3["traefik-41-2-0"]
                end

                subgraph DMW["mcs-403-mcsdep-diamond-workload"]
                    M4["kserve-resources-0-18-0"]
                end

                %% dependsOn on the edge, not in the title: a two-line subgraph
                %% title overlaps the box below it.
                DMC -- "dependsOn" --> DMR
                DMC -- "dependsOn" --> DMP
                DMR -- "dependsOn" --> DMW
                DMP -- "dependsOn" --> DMW
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
    class DMC,DMR,DMP,DMW,T1,T2,T3,T4,M1,M2,M3,M4 pink
    class C1,C2 green
    class W2 bare
```

Defined in [`403_mcsdep_diamond.yaml`](403_mcsdep_diamond.yaml).
