# Copied from k0rdent/catalog

These are taken verbatim from [`k0rdent/catalog`](https://github.com/k0rdent/catalog)
`scripts/`, so the two repositories do not grow two different answers to the same
provider question. They are kept here unedited on purpose: re-syncing is then a
copy, not a merge.

| here | catalog |
|---|---|
| `check_aws_creds.sh` | `scripts/check_aws_creds.sh` |
| `check_azure_creds.sh` | `scripts/check_azure_creds.sh` |
| `check_gcp_creds.sh` | `scripts/check_gcp_creds.sh` |
| `setup_provider_credential.sh` | `scripts/setup_provider_credential.sh` |
| `export_cluster_template_names.sh` | `scripts/export_cluster_template_names.sh` |
| `list_cld_resources_aws.sh` | `scripts/list_cld_resources_aws.sh` |
| `list_cld_resources_azure.sh` | `scripts/list_cld_resources_azure.sh` |
| `list_cld_resources_gcp.sh` | `scripts/list_cld_resources_gcp.sh` |

`scripts/config/{aws,azure,gcp}-cld.yaml` come from catalog's `scripts/config/`
the same way.

They expect to be run from the repository root with `KUBECONFIG` already pointing
at the management cluster, and they read `TEST_MODE` and the provider variables
from the environment. `scripts/steps/deploy_cloud_cluster.sh` is what calls them.

What was **not** copied, and why:

- `deploy_cld.sh` / `remove_cld.sh` — their adopted half hardcodes one container
  name, network and port, so two environments on one host collide.
  `scripts/steps/deploy_adopted_cluster.sh` does the same job scoped per `$KCM`.
  The cloud half is small enough that `deploy_cloud_cluster.sh` follows it
  directly rather than wrapping it.
- `wait_for_cld.sh`, `wait_for_cluster_removal.sh`, `wait_for_servicetemplate.sh`,
  `wait_for_deployment.sh`, `retry.sh` — `scripts/lib/k8s.sh` already has these
  taking a kind, name, namespace and timeout, and they are used throughout.
  Copying the single-purpose versions would add a second way to wait.
