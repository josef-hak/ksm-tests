# 5.4. Stepwise chain (504_stepwise_chain)

## Tested steps

1. Install the ServiceTemplates for all three versions and wait for each to report `valid`.
2. Create the ServiceTemplateChain: `1.20.2 → 1.20.3 → 1.21.1`.
3. Deploy one MultiClusterService with `cert-manager` on `1.20.2`, pods ready.
4. Ask for `1.21.1`: the helm release has to end up on that version, `deployed`.
5. Check the helm history for `1.20.3` — the chain says the route goes through it,
   so reaching the target without it is a failure. History, not live watching: the
   intermediate version can be too brief to catch.
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
                T1["cert-manager-1-20-2<br/>cert-manager-1-20-3<br/>cert-manager-1-21-1"]
            end

            subgraph D3["Create ServiceTemplateChain"]
                H1["cert-manager-1-20-2<br/>&nbsp;&nbsp;&nbsp;availableUpgrades: 1.20.3<br/>cert-manager-1-20-3<br/>&nbsp;&nbsp;&nbsp;availableUpgrades: 1.21.1<br/>cert-manager-1-21-1"]
            end

            subgraph D2["Deploy MultiClusterService"]
                direction TB
                M1["cert-manager 1.20.2"]
            end

            D1 --> D3 --> D2
        end
    end

    subgraph P3["3) Upgrade services"]
        subgraph W3[" "]
            direction LR
            U1["Direct upgrade<br/>(skipped)"]

            subgraph U2["Upgrade via ServiceTemplateChain"]
                direction TB
                S1["ask for 1.21.1"] --> S2["via 1.20.3<br/>checked in helm history"]
            end
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

    class P1,U1 off
    class D1,D2,D3,T1,H1,M1 pink
    class U2,S1,S2 amber
    class C1,C2 green
    class W2,W3 bare
```

> [!WARNING]
> Known failure on KCM 1.11.0 in `3) Upgrade services`: the release goes straight
> from `1.20.2` to `1.21.1` in one helm upgrade. The chain is consulted — `502` and
> `503` prove that — but it constrains which versions may be reached, not the route
> taken.

Defined in [`504_stepwise_chain.yaml`](504_stepwise_chain.yaml).
