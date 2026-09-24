# 2.1. Service dependency (201_svcdep)

## Description

A valid `dependsOn` chain: every service is correct, so all of them must land — and
in the declared order, not at once. The chain is the one from catalog's `apps/kserve`:
cert-manager issues the webhook certificates, the CRDs have to exist before the
controller that owns instances of them.

```mermaid
flowchart LR
    A["cert-manager<br/>1.20.2"] --> B["kserve-crd<br/>v0.18.0"] --> C["kserve-resources<br/>v0.18.0"]

    classDef svc fill:#ede9fe,stroke:#7c3aed,color:#0b1220
    class A,B,C svc
```

## What is asserted

| Step | Check |
|---|---|
| Install ServiceTemplates | each of the three `ServiceTemplate` objects reports `valid` before anything is deployed |
| Deploy MultiClusterService | KCM turns the MCS into a `ServiceSet` — a missing one means the selector never matched |
| | every service has a **deployed helm release** in the target cluster, waited for in the declared order; the namespace existing is not enough, because namespaces outlive the scenario that made them |
| | pods matching `waitForPods` are ready — `cert-manager-` and `kserve-controller-manager-`; `kserve-crd` ships only CRDs, so it has nothing to wait for |
| | the MCS reports `ClusterInReadyState`, so KCM has accepted the rollout rather than the test having merely seen the workloads come up |
| Remove services | the MCS disappears, and no `ServiceSet` of its own survives it |
| | no helm release is left for any of the three services — a release record can outlive an emptied namespace and break the next scenario |
| | no Deployment, DaemonSet or StatefulSet is left in `cert-manager` or `kserve` |

What this proves about dependencies is indirect but real: a dependent that KSM
released too early cannot reach a deployed release while the chart it needs is
missing, so the per-service wait fails and the scenario goes red. The order itself
is asserted directly in the unit tests; here it is the end state that has to hold.

> [!NOTE]
> The copy of cert-manager sets `crds.enabled: false` and a `fullnameOverride`,
> because KCM runs its own cert-manager here and its helm release already owns the
> cert-manager CRDs. Self-management means the services land in a cluster that is
> not empty.

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

Grey phases are not part of this scenario: the environment is built once and shared
by every scenario, and this one declares no `upgrade:` block, so nothing is upgraded.

## Run it

```bash
SCENARIO=201_svcdep ./scripts/run_scenario.sh
```

> [!WARNING]
> CI currently skips the `4) Clean up: Remove services` step for this scenario —
> the teardown wedges on the MCS finalizer, because the chart owning the CRDs is
> uninstalled before the release still holding a CR of them
> ([kcm#3021](https://github.com/k0rdent/kcm/issues/3021)). Known to fail on
> KCM 1.11.0, fixed between v1.11.0 and v1.12.0-rc1.

Defined in [`201_svcdep.yaml`](201_svcdep.yaml).
