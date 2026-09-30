# 5.2. Chain offering no upgrades (502_chain_boundary)

## Tested steps

1. Install the ServiceTemplates for `1.20.2` and `1.21.1` and wait for each to report
   `valid` — the target exists as a template, only the chain refuses it.
2. Create the ServiceTemplateChain listing `1.20.2` alone, deliberately with no
   `availableUpgrades`.
3. Deploy one MultiClusterService with `cert-manager` on `1.20.2`, pods ready.
4. Ask for `1.21.1` and watch for 120s: the release must stay on `1.20.2`. A refusal is
   the absence of a change, so it needs the whole window; any move is an immediate
   failure. KCM keeps the stored version rather than erroring, so nothing-changed is
   the only observable.
5. Remove the services: MCS, ServiceSet, helm release and workloads all gone.

## Scenario schema

```mermaid
%%{init: {'flowchart': {'padding': 10, 'nodeSpacing': 18, 'rankSpacing': 28, 'subGraphTitleMargin': {'top': 6, 'bottom': 10}}}}%%
flowchart LR
    P1["1) Build environment"]

    subgraph P2["2) Deploy services"]
        subgraph W2[" "]
            direction LR
            subgraph D1["Install ServiceTemplates"]
                T1["cert-manager-1-20-2<br/>cert-manager-1-21-1"]
            end

            subgraph D3["Create ServiceTemplateChain"]
                H1["cert-manager-1-20-2<br/>&nbsp;&nbsp;&nbsp;availableUpgrades: none"]
            end

            subgraph D2["Deploy MultiClusterService"]
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
                S1["ask for 1.21.1"] --> S2["rejected<br/>still on 1.20.2 after 120s"]
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

Defined in [`502_chain_boundary.yaml`](502_chain_boundary.yaml).
