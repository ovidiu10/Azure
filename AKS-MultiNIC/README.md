# AKS multi-NIC with managed DRANET (public preview)

A parameterized, private-IP demonstration: add a Linux user node pool to an
existing AKS cluster, then assign one of its secondary NICs exclusively to a pod
using Kubernetes Dynamic Resource Allocation (DRA). No Multus installation,
custom CNI, public IP, or manual DRANET deployment is needed.

All subscription IDs, resource names, subnet IDs, VM size, namespace, workload
names, and container image are inputs. There are no environment-specific values
or private references. "standard-secondary-nic" is the public AKS DeviceClass,
not a customer resource name. JSON is used for both CLI input and Kubernetes
manifests; kubectl accepts JSON as well as YAML.

This is an educational community sample, not an official Microsoft product.
Public preview is not intended for production and is excluded from AKS SLAs.
Creating the pool incurs VM, disk, and networking costs. A failed deployment
does not automatically roll back or delete resources.

## Prerequisites

* Azure CLI, kubectl, and the latest aks-preview CLI extension.
* Choose one: Bash 3.2+ and jq for azure-cli/, PowerShell 7+ for powershell/,
  or Python 3.10+ for python/ (standard library only; no pip install).
* The direct Azure CLI version runs on Linux/macOS Bash and Windows Git Bash
  or WSL. A .sh file does not run directly in Windows Command Prompt or
  PowerShell. Use Git Bash/WSL, or choose the powershell/ version for PowerShell.
  It is not a Python wrapper and does not require a separate Python install.
* On Windows, use the official Azure CLI MSI or WinGet installation and native
  kubectl.exe with Git Bash. The Bash and Python versions bypass az.cmd using
  the MSI's bundled interpreter, avoiding cmd.exe argument expansion.
  With WSL, install az, kubectl, and jq INSIDE the Linux distribution and sign
  in there; do not mix Windows and WSL binaries or cached login contexts.
  Linux/macOS use az, kubectl, and (for Bash) jq on their shell's PATH.
* An existing Kubernetes 1.35+ AKS cluster with AKS-managed Azure CNI, optionally
  powered by Cilium, and a bring-your-own VNet.
* Existing node and secondary subnets in that SAME VNet and subscription.
* A VM size available in the cluster region supporting at least
  1 + secondarySubnetIds.Count NICs; sufficient VM quota and IP address capacity.
* AKS cluster identity permissions to join the secondary subnet(s), normally
  Network Contributor on the VNet. Ask the resource owner to grant these if
  needed; the sample does not change role assignments.
* Azure permission to read the cluster, subnets, and SKUs and add a node pool.
  Kubernetes permission to read nodes/device classes and manage pods,
  ResourceClaimTemplates, and ResourceClaims in an existing namespace.
* A trusted Linux diagnostic image containing sh and ip (including ip -j).
  The public guide uses nicolaka/netshoot; choose an explicit supported tag or
  digest and review the image before use. :latest is rejected.
* A namespace allowing that image to run. The sample drops capabilities,
  disables privilege escalation, and does not mount a service-account token,
  but does not force a non-root UID; restricted Pod Security admission may
  require an appropriate image and corresponding securityContext changes.

The Learn overview states 1.34+ for upstream DRA GA, but the AKS configuration
guide requires 1.35+. This sample uses the stricter 1.35+ requirement.
Check the linked public guide again before deployment as preview details change.

## Version folders

- [`azure-cli/`](azure-cli/) — Bash Azure CLI and kubectl scripts (requires `jq`)
- [`powershell/`](powershell/) — PowerShell 7 implementation
- [`python/`](python/) — Python 3.10+ implementation and tests
- [`shared/`](shared/) — Common `config.example.json` and `workload.template.json`

All implementations use the same shared configuration and workload template.
Keep the shared folder beside the version folders; do not copy an entrypoint
alone. Each version writes output to its own generated subfolder by default.
Unless indicated otherwise, commands below run from the AKS-MultiNIC root.

## Subscription preparation (explicit opt-in)

These commands change subscription registration or local CLI configuration.
Run them yourself after choosing the subscription; do not paste placeholders
without replacing them.

```bash
az login
az extension add --name aks-preview
az extension update --name aks-preview
az feature register \
  --subscription "<subscription-id>" \
  --namespace Microsoft.ContainerService \
  --name NetworkingMultiNICPreview
az feature show \
  --subscription "<subscription-id>" \
  --namespace Microsoft.ContainerService \
  --name NetworkingMultiNICPreview \
  --query properties.state -o tsv
```

Wait until the state is Registered, then refresh the provider:

```bash
az provider register \
  --subscription "<subscription-id>" \
  --namespace Microsoft.ContainerService
az provider show \
  --subscription "<subscription-id>" \
  --namespace Microsoft.ContainerService \
  --query registrationState -o tsv
```

Wait until the provider registrationState is Registered as well.
Prepare an existing dedicated namespace on the target cluster if necessary:

```bash
az aks get-credentials \
  --subscription "<subscription-id>" \
  --resource-group "<resource-group-name>" \
  --name "<existing-aks-cluster-name>"
kubectl config current-context
kubectl create namespace "<kubernetes-namespace>"
```

The sample itself uses a temporary, isolated kubeconfig; it does not switch or
overwrite the user's current kubectl context. Microsoft Entra-integrated
clusters may additionally require kubelogin and an interactive sign-in.

## Configure

From this directory, copy shared/config.example.json to shared/config.json:

Windows PowerShell:

```powershell
Copy-Item .\shared\config.example.json .\shared\config.json
```

Linux/macOS:

```bash
cp shared/config.example.json shared/config.json
```

Edit every placeholder in shared/config.json. Use a NEW nodePoolName (1-12 lowercase
letters/digits, starting with a letter). The namespace must already exist;
podName and claimTemplateName must not already exist there.
One secondarySubnetIds entry creates one secondary NIC per node. Repeat an ID
to create multiple NICs on the same subnet, or supply IDs from different subnets
in the same VNet. The sample pod requests ONE secondary NIC, not every NIC.
All NICs are private: there is deliberately no public-IP configuration.

## Azure CLI version (Bash)

From Bash on Linux/macOS, Git Bash on Windows, or a WSL Linux terminal:

### Short Azure CLI example

The following is a standalone Bash walkthrough for an existing AKS cluster.
Replace every value before running. Requires Kubernetes 1.35+, Azure CNI, a
registered preview feature, `aks-preview`, `kubectl`, and `jq`. All subnets must
be in the same VNet; the VM size must support at least two NICs.

```bash
SUBSCRIPTION_ID="<subscription-id>"
RESOURCE_GROUP="<resource-group-name>"
CLUSTER_NAME="<existing-aks-cluster-name>"
NODE_POOL="<new-linux-node-pool-name>"
VM_SIZE="<vm-size-supporting-at-least-two-nics>"
SECONDARY_SUBNET_ID="<secondary-subnet-resource-id>"
NAMESPACE="<existing-kubernetes-namespace>"
POD_NAME="<pod-name>"
CLAIM_TEMPLATE="<resource-claim-template-name>"
IMAGE="<diagnostic-image-with-sh-and-ip:tag>"

# Git Bash on Windows: preserve Azure resource IDs passed to native az/kubectl.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

az aks nodepool add --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$CLUSTER_NAME" \
  --name "$NODE_POOL" \
  --mode User --os-type Linux --node-count 1 \
  --node-vm-size "$VM_SIZE" \
  --secondary-network-interfaces \
  "[{\"type\":\"Standard\",\"vnetSubnetId\":\"$SECONDARY_SUBNET_ID\"}]"

# Use an isolated kubeconfig so your current kubectl context is unchanged.
KUBECONFIG_SAMPLE="$(mktemp)"
trap 'rm -f "$KUBECONFIG_SAMPLE"' EXIT
az aks get-credentials --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
  --file "$KUBECONFIG_SAMPLE"
k() { kubectl --kubeconfig "$KUBECONFIG_SAMPLE" "$@"; }

k apply -f - <<EOF
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: $CLAIM_TEMPLATE
  namespace: $NAMESPACE
spec:
  spec:
    devices:
      requests:
      - name: secondary-nic
        exactly:
          deviceClassName: standard-secondary-nic
          allocationMode: ExactCount
          count: 1
---
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  namespace: $NAMESPACE
spec:
  nodeSelector:
    kubernetes.azure.com/agentpool: $NODE_POOL
  resourceClaims:
  - name: secondary-nic
    resourceClaimTemplateName: $CLAIM_TEMPLATE
  containers:
  - name: diagnostics
    image: "$IMAGE"
    command: ["sh", "-c", "sleep infinity"]
    resources:
      claims:
      - name: secondary-nic
EOF

k -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD_NAME" --timeout=600s
k -n "$NAMESPACE" exec "$POD_NAME" -- ip address show
```

Expect `eth0` and an additional addressed interface. Each secondary NIC is
exclusive to one pod. Network policies apply only to the primary interface;
secure secondary-subnet traffic with appropriate NSG/firewall rules. This is
public-preview functionality, not intended for production, and the node pool
incurs ongoing costs. Remove the sample pod and claim after use; delete the
node pool separately only after confirming nothing else uses it.

### Full Bash CLI

For automated preflight, live preview checks, and a guided workload lifecycle,
use the Bash script instead of the short manual walkthrough:

```bash
bash azure-cli/aks-multinic.sh --help
bash azure-cli/aks-multinic.sh render --config shared/config.json
bash azure-cli/aks-multinic.sh deploy --config shared/config.json --dry-run
bash azure-cli/aks-multinic.sh deploy --config shared/config.json
bash azure-cli/aks-multinic.sh verify --config shared/config.json
bash azure-cli/aks-multinic.sh remove-workload --config shared/config.json --dry-run
bash azure-cli/aks-multinic.sh remove-workload --config shared/config.json
```

Windows Git Bash example to enter the repository (replace the location):

```bash
cd /c/path/to/Azure/AKS-MultiNIC
```

Git Bash accepts /c/... paths or quoted Windows paths for --config and
--output-dir. The script converts file paths for native tools and disables
MSYS rewriting of Azure /subscriptions/... IDs and Kubernetes pod/name values.
It normalizes native Windows CRLF output. WSL uses ordinary Linux paths.

The script is compatible with macOS's built-in Bash 3.2; no GNU-only realpath,
mapfile, jq-through-Python, or PowerShell is required. Install jq separately
if it is not already available. Azure Cloud Shell Bash is also suitable when
the sample files and required preview extension are available there.

## Python CLI (cross-platform)

python/aks_multinic.py runs Azure CLI and kubectl operations on Windows,
Linux, and macOS without requiring PowerShell, Bash, jq, or Python packages.
Do not apply shared/workload.template.json directly: all entrypoints populate
its placeholders during rendering.

Windows (PowerShell or Command Prompt, using Python 3.10+):

```powershell
python python\aks_multinic.py --help
python python\aks_multinic.py render --config shared\config.json
python python\aks_multinic.py deploy --config shared\config.json --dry-run
python python\aks_multinic.py deploy --config shared\config.json
python python\aks_multinic.py verify --config shared\config.json
python python\aks_multinic.py remove-workload --config shared\config.json --dry-run
python python\aks_multinic.py remove-workload --config shared\config.json
```

Linux/macOS:

```bash
python3 python/aks_multinic.py --help
python3 python/aks_multinic.py render --config shared/config.json
python3 python/aks_multinic.py deploy --config shared/config.json --dry-run
python3 python/aks_multinic.py deploy --config shared/config.json
python3 python/aks_multinic.py verify --config shared/config.json
python3 python/aks_multinic.py remove-workload --config shared/config.json --dry-run
python3 python/aks_multinic.py remove-workload --config shared/config.json
```

For both Bash and Python, render is offline. --dry-run makes no Azure/kubectl
calls or file writes (Bash uses local jq to validate configuration) and does
not perform live preflight. deploy and remove-workload show the target and
require typing yes in an interactive terminal. For an intentional unattended
run, add --yes; without it, noninteractive changes fail rather than hanging.
verify reads the cluster but does not deploy or delete workload resources.

Optional --output-dir selects the rendered file directory; quote paths with
spaces. Optional --timeout accepts 30-3600 seconds (default 600) for readiness
and pod deletion, not the duration of Azure provisioning. No current Azure
subscription or kubectl context is changed. Commands fail with a nonzero exit
code on invalid configuration, missing tools, or deployment/verification errors.
Failed/interrupted deployment is not automatically rolled back.

## PowerShell 7 CLI

From PowerShell 7, render offline:

```powershell
.\powershell\Invoke-AksMultiNicSample.ps1 -ConfigPath .\shared\config.json -Action Render
```

All versions write secondary-nics.json and workload.json in their own generated
folder. Local config.json and generated folders are excluded from Git because they contain
your deployment identifiers. Do not publish credentials or generated configs.

Preview the deployment target without cloud writes:

```powershell
.\powershell\Invoke-AksMultiNicSample.ps1 -ConfigPath .\shared\config.json -Action Deploy -WhatIf
```

WhatIf, like --dry-run, does not perform live preflight.

Create the user node pool and deploy the workload:

```powershell
.\powershell\Invoke-AksMultiNicSample.ps1 -ConfigPath .\shared\config.json -Action Deploy
```

All versions check version, CNI, extension support, feature registration, VNet
scope, VM NIC capacity, and name collisions before creating the pool. Quota,
regional preview availability, permissions, and capacity are ultimately
validated by Azure. It waits for the managed DeviceClass and pod readiness.
Generated manifests pin the pod to your chosen Linux pool. Other workloads can
also use this pool; it is not tainted or reserved exclusively for this sample.

Verify again later:

```powershell
.\powershell\Invoke-AksMultiNicSample.ps1 -ConfigPath .\shared\config.json -Action Verify
```

Expected: eth0 (the CNI interface), at least one additional interface with a
global-scope IP address, and an allocated ResourceClaim. The script prints
interface/address JSON, IPv4 routes, and claims. It fails if the additional
addressed interface is absent. Its name is not assumed to be eth1.
This demonstrates interface allocation, NOT application connectivity,
throughput, latency, internet reachability, or an isolation certification.

To test an authorized private peer, inspect the reported secondary interface
and routes, then bind your application or diagnostic tool to that interface.
Use a separate explicit kubeconfig for manual kubectl exec commands. Do not
assume default-route traffic uses the secondary NIC, change cluster routes
blindly, or send test traffic to an unrelated public endpoint.

## Design and security boundaries

Primary subnet -> node primary NIC -> Azure CNI -> pod eth0
Secondary subnet -> node secondary NIC -> DRANET/DRA -> pod secondary interface

* Secondary NICs are exclusively assigned, never shared between pods. A node
  with N secondary NICs can serve at most N simultaneous pods requesting one
  NIC each. Ordinary CNI-only pods are not subject to that specific bound.
* When the pod terminates, its secondary NIC becomes available again.
* Linux only. All NICs must be in the same VNet. This sample intentionally
  requires BYO VNet; managed-VNet preview supports only the primary subnet.
* NIC configuration is immutable: create a new pool to change the NIC list.
* AKS network policies protect ONLY the primary interface. Different subnets
  alone do not isolate traffic: Azure's default NSG rules allow VNet traffic.
  Resource owners must design NSG/firewall rules for the secondary subnet,
  allowing only intended private peers and preserving required platform access.
* A private NIC does not mean "no outbound internet": subnet routing and Azure
  outbound configuration still determine reachability.
* Public IPs on secondary NICs bypass load balancer/SNAT protection. That
  scenario is deliberately excluded here; it needs a separate security design.
* Configurations with multiple secondary subnets do not imply selection of a
  specific subnet for this pod: the default DeviceClass can allocate any
  matching secondary NIC on the selected node. Use one secondary subnet for
  a deterministic subnet demonstration.

## Offline CLI tests

Python tests, from the python folder:

Windows:

```powershell
cd python
python -B -m unittest -q test_aks_multinic
```

Linux/macOS:

```bash
cd python
python3 -B -m unittest -q test_aks_multinic
```

These standard-library tests mock Azure and Kubernetes commands. They never
authenticate, provision infrastructure, or send traffic to workloads.

Bash integration tests, from the AKS-MultiNIC root in Bash (requires jq):

```bash
bash azure-cli/test-aks-multinic.sh
```

These tests use exported az/kubectl mocks, including simulated Windows CRLF
output. They render temporary fixtures and check the lifecycle without calling
the real Azure CLI or changing cluster state.

## Public references

Announcement:
https://techcommunity.microsoft.com/blog/azurenetworkingblog/multi-nic-support-on-aks-powered-by-dranet-%E2%80%93-now-in-public-preview/4563257

Video, "Introducing AKS Multi-NIC with DRANET":
https://www.youtube.com/watch?v=vnTG964NCL4

Configuration guide (authoritative for commands and prerequisites):
https://learn.microsoft.com/azure/aks/configure-multiple-network-interfaces-for-pods

Overview, architecture, preview limitations, and public-IP warning:
https://learn.microsoft.com/azure/aks/multiple-network-interfaces-for-pods-overview

Upstream project:
https://github.com/kubernetes-sigs/dranet

The implementation follows public Learn API shapes rather than copying the
announcement's abbreviated JSON/YAML. The video is introductory context, not a
source of additional implementation requirements.

## Troubleshooting

Use the kubeconfig for the target cluster when inspecting nodes, DRANET, and
claims. Substitute your actual kubeconfig path, pod, and namespace:

```bash
kubectl --kubeconfig "<kubeconfig-path>" get nodes -L kubernetes.azure.com/agentpool
kubectl --kubeconfig "<kubeconfig-path>" get deviceclasses
kubectl --kubeconfig "<kubeconfig-path>" get resourceslices
kubectl --kubeconfig "<kubeconfig-path>" get daemonset -A
kubectl --kubeconfig "<kubeconfig-path>" get pods -A -o wide
kubectl --kubeconfig "<kubeconfig-path>" describe pod "<pod-name>" -n "<namespace>"
kubectl --kubeconfig "<kubeconfig-path>" get resourceclaims -n "<namespace>"
kubectl --kubeconfig "<kubeconfig-path>" get events -n "<namespace>" --sort-by=.lastTimestamp
```

A Pending pod can indicate no free NICs, an unready DRANET driver, pool
capacity, admission rejection, or an image pull error. Inspect pod events
before changing anything. A deployment timeout does not remove the new node
pool; it remains billable. Diagnose the pool and workload before retrying.

## Cleanup

Remove only the sample pod and ResourceClaimTemplate. Confirm the configured
names refer to this sample, and do not remove a claim template used by other
workloads. Kubernetes garbage-collects the per-pod ResourceClaim.

Bash (from the sample root):

```bash
bash azure-cli/aks-multinic.sh remove-workload --config shared/config.json --dry-run
bash azure-cli/aks-multinic.sh remove-workload --config shared/config.json
```

Python (Windows):

```powershell
python python\aks_multinic.py remove-workload --config shared\config.json --dry-run
python python\aks_multinic.py remove-workload --config shared\config.json
```

Python (Linux/macOS):

```bash
python3 python/aks_multinic.py remove-workload --config shared/config.json --dry-run
python3 python/aks_multinic.py remove-workload --config shared/config.json
```

PowerShell 7:

```powershell
.\powershell\Invoke-AksMultiNicSample.ps1 -ConfigPath .\shared\config.json -Action RemoveWorkload -WhatIf
.\powershell\Invoke-AksMultiNicSample.ps1 -ConfigPath .\shared\config.json -Action RemoveWorkload -Confirm
```

Workload cleanup does not remove the node pool, which continues to incur
costs. After confirming no other workload uses it, delete only the sample pool:

```bash
az aks nodepool delete \
  --subscription "<subscription-id>" \
  --resource-group "<resource-group-name>" \
  --cluster-name "<existing-aks-cluster-name>" \
  --name "<sample-node-pool-name>"
```

Keep the existing cluster, VNet, subnets, and namespace. Do not delete the
resource group as a shortcut.
