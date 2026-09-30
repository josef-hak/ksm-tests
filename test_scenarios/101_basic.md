# 1.1. Basic service (101_basic)

## Tested steps

1. Install the ServiceTemplate for `traefik` and wait for it to report `valid`.
2. Deploy one MultiClusterService carrying that single service.
3. `traefik` — deployed helm release in the child cluster, pods ready. The release,
   not the namespace: namespaces linger after earlier scenarios.
4. The MCS reports `ClusterInReadyState`.
5. Remove the services: MCS, ServiceSet, helm release and workloads all gone.

## Scenario schema

```mermaid
%%{init: {'flowchart': {'padding': 10, 'nodeSpacing': 18, 'rankSpacing': 28}}}%%
flowchart LR
    P1["1) Build environment"]

    subgraph P2["2) Deploy services"]
        subgraph W2[" "]
            direction LR
            subgraph D1["Install ServiceTemplates"]
                T1["traefik-41-2-0"]
            end

            subgraph D2["Deploy MultiClusterService"]
                M1["traefik"]
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
    class D1,D2,T1,M1 pink
    class C1,C2 green
    class W2 bare
```

Defined in [`101_basic.yaml`](101_basic.yaml).
