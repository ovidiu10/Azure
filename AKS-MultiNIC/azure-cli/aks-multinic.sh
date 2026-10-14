#!/usr/bin/env bash
# Bash 3.2+, jq, Azure CLI, and kubectl; no separate Python or PowerShell runtime.
set -Eeuo pipefail
umask 077

script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
shared_directory="$script_directory/../shared"
output_directory="$script_directory/generated"
config_path=
action=
timeout=600
dry_run=false
confirmed=false
temporary_directory=
windows_shell=false

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
cleanup() {
    if [[ -n "$temporary_directory" ]]; then
        rm -rf -- "$temporary_directory"
    fi
}
command_error() {
    local status=$1 line=$2
    printf 'Error: command failed at line %s (exit %s). Review the error above.\n' "$line" "$status" >&2
    if [[ "$action" == deploy ]]; then
        printf 'Deployment is not rolled back; any created node pool remains billable.\n' >&2
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'command_error "$?" "$LINENO"' ERR
trap 'printf "Interrupted; any created resources remain.\n" >&2; exit 130' INT
trap 'printf "Terminated; any created resources remain.\n" >&2; exit 143' TERM

usage() {
    printf '%s\n' \
        'Usage: bash aks-multinic.sh ACTION --config FILE [OPTIONS]' \
        'Actions: render, deploy, verify, remove-workload' \
        'Options:' \
        '  --output-dir DIR   Generated files (default: azure-cli/generated)' \
        '  --timeout SECONDS  Readiness/deletion timeout, 30-3600 (default: 600)' \
        '  --dry-run          No tool calls or writes; not a live preflight' \
        '  --yes              Confirm deployment/deletion noninteractively' \
        '  -h, --help         Show help' \
        'Windows: run in Git Bash or WSL; Linux/macOS: run in Bash 3.2+.' \
        'Requires jq; live actions also require Azure CLI and kubectl.'
}
require_value() {
    [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 requires a value."
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --config) require_value "$@"; config_path=$2; shift 2 ;;
        --output-dir) require_value "$@"; output_directory=$2; shift 2 ;;
        --timeout) require_value "$@"; timeout=$2; shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        --yes) confirmed=true; shift ;;
        render|deploy|verify|remove-workload)
            [[ -z "$action" ]] || die 'Specify exactly one action.'
            action=$1; shift ;;
        *) die "Unknown argument: $1" ;;
    esac
done
[[ -n "$action" && -n "$config_path" ]] || { usage >&2; die 'An action and --config are required.'; }
[[ "$timeout" =~ ^[0-9]{2,4}$ ]] || die 'timeout must be an integer between 30 and 3600.'
timeout=$((10#$timeout))
(( timeout >= 30 && timeout <= 3600 )) || die 'timeout must be between 30 and 3600.'
command -v jq >/dev/null || die 'jq is required; install it before running this version.'
# Native Windows tools emit CRLF; keep captured values and rendered JSON portable.
jq() { command jq "$@" | tr -d '\r'; }

case "${OSTYPE:-}" in
    msys*|cygwin*)
        windows_shell=true
        command -v cygpath >/dev/null || die 'Git Bash requires cygpath for native Windows file paths.'
        # Do not rewrite Azure /subscriptions IDs or Kubernetes pod/name arguments.
        export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
        config_path=$(cygpath -u "$config_path")
        output_directory=$(cygpath -u "$output_directory")
        ;;
esac
native_path() {
    if "$windows_shell"; then cygpath -am "$1"; else printf '%s\n' "$1"; fi
}
[[ -f "$config_path" ]] || die 'Configuration file does not exist.'
[[ "$output_directory" == /* ]] || output_directory="$PWD/$output_directory"

config=$(jq -ce -s '
    if length == 1 and (.[0] | type == "object")
    then .[0] else error("Configuration must contain one JSON object") end
' "$(native_path "$config_path")")
if ! jq -e '
    . as $c |
    ["subscriptionId", "resourceGroup", "clusterName", "nodePoolName", "namespace",
     "podName", "claimTemplateName", "vmSize", "image"] |
    all(.[]; $c[.] |
        if type == "string" then
            (length > 0 and test("\\S") and (test("[<>]") | not) and
             (startswith("-") | not) and (explode | all(. >= 32)))
        else false end)
' <<< "$config" >/dev/null; then
    die 'Supply every required string without placeholders, control characters, or leading hyphens.'
fi
if ! jq -e '
    (.subscriptionId | test("^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$")) and
    (.nodePoolName | test("^[a-z][a-z0-9]{0,11}$")) and
    ([.namespace, .podName, .claimTemplateName] |
        all(.[]; length <= 63 and test("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$"))) and
    (.nodeCount | type == "number" and . == floor and . >= 1 and . <= 100) and
    (.image | (test("\\s") | not) and (test(":latest$"; "i") | not) and
        if contains("@") then test("^[^@\\s]+@sha256:[a-fA-F0-9]{64}$")
        else test("^[^@\\s]+:[^/:\\s]+$") end) and
    (.secondarySubnetIds | type == "array" and length > 0 and
        all(.[]; if type == "string" then (explode | all(. >= 32)) else false end))
' <<< "$config" >/dev/null; then
    die 'Invalid GUID, names, nodeCount, pinned image, or secondarySubnetIds array. See README.md.'
fi

subscription=$(jq -r '.subscriptionId' <<< "$config")
resource_group=$(jq -r '.resourceGroup' <<< "$config")
cluster_name=$(jq -r '.clusterName' <<< "$config")
node_pool=$(jq -r '.nodePoolName' <<< "$config")
namespace=$(jq -r '.namespace' <<< "$config")
pod_name=$(jq -r '.podName' <<< "$config")
claim_name=$(jq -r '.claimTemplateName' <<< "$config")
vm_size=$(jq -r '.vmSize' <<< "$config")
node_count=$(jq -r '.nodeCount' <<< "$config")
nic_count=$(jq -r '.secondarySubnetIds | length' <<< "$config")
subnet_list=$(jq -r '.secondarySubnetIds[]' <<< "$config")
secondary_vnet=
subnet_pattern='^(/subscriptions/([^/]+)/resourceGroups/[^/]+/providers/Microsoft\.Network/virtualNetworks/[^/]+)/subnets/[^/<>]+$'
shopt -s nocasematch
while IFS= read -r subnet; do
    [[ "$subnet" =~ $subnet_pattern ]] || die 'Each secondary subnet must be a complete Azure subnet resource ID.'
    [[ "${BASH_REMATCH[2]}" == "$subscription" ]] || die 'Secondary subnets must use the configured subscription.'
    current_vnet=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
    if [[ -z "$secondary_vnet" ]]; then secondary_vnet=$current_vnet; fi
    [[ "$current_vnet" == "$secondary_vnet" ]] || die 'All secondary subnets must be in the same VNet.'
done <<< "$subnet_list"
shopt -u nocasematch

render() {
    mkdir -p -- "$output_directory"
    nic_path="$output_directory/secondary-nics.json"
    manifest_path="$output_directory/workload.json"
    jq '[.secondarySubnetIds[] | {type: "Standard", vnetSubnetId: .}]' <<< "$config" > "$nic_path"
    jq --argjson cfg "$config" '
        .items[0].metadata = {name: $cfg.claimTemplateName, namespace: $cfg.namespace} |
        .items[1].metadata = {name: $cfg.podName, namespace: $cfg.namespace} |
        .items[1].spec.nodeSelector["kubernetes.azure.com/agentpool"] = $cfg.nodePoolName |
        .items[1].spec.resourceClaims[0].resourceClaimTemplateName = $cfg.claimTemplateName |
        .items[1].spec.containers[0].image = $cfg.image
    ' "$(native_path "$shared_directory/workload.template.json")" > "$manifest_path"
    printf 'Rendered: %s\nRendered: %s\n' "$nic_path" "$manifest_path"
}
target="$subscription/$resource_group/$cluster_name, namespace $namespace"
if "$dry_run"; then
    printf 'Dry run: %s on %s; output directory %s. No commands or writes.\n' "$action" "$target" "$output_directory"
    exit 0
fi
if [[ "$action" == render ]]; then render; exit 0; fi
if [[ "$action" == deploy || "$action" == remove-workload ]] && ! "$confirmed"; then
    if [[ "$action" == deploy ]]; then
        printf "Create billable pool '%s' and pod '%s' on %s.\n" "$node_pool" "$pod_name" "$target"
    else
        printf "Delete pod '%s' and claim template '%s' on %s.\n" "$pod_name" "$claim_name" "$target"
    fi
    [[ -t 0 ]] || die 'Noninteractive changes require --yes; review --dry-run first.'
    printf 'Type yes to continue: '
    IFS= read -r answer
    [[ "$answer" == yes ]] || { printf 'Cancelled; no commands or writes.\n'; exit 0; }
fi

if az_executable=$(command -v az); then
    :
elif az_executable=$(command -v az.cmd); then
    :
else
    die 'Azure CLI was not found on PATH.'
fi
az_command=("$az_executable")
if "$windows_shell"; then
    case "$az_executable" in
        *.cmd|*.bat)
            installer_python="$(dirname "$az_executable")/../python.exe"
            [[ -f "$installer_python" ]] || die 'Use the official Azure CLI MSI/WinGet installation in Git Bash.'
            az_command=("$installer_python" -X utf8 -IBm azure.cli)
            export AZ_INSTALLER=MSI
            ;;
    esac
fi
command -v kubectl >/dev/null || die 'kubectl was not found on PATH.'
az_resource() { "${az_command[@]}" "$@" --subscription "$subscription" --only-show-errors | tr -d '\r'; }
kubectl_cluster() { kubectl --kubeconfig "$(native_path "$kubeconfig_path")" "$@" | tr -d '\r'; }
cluster_json=$(az_resource aks show -g "$resource_group" -n "$cluster_name" -o json)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/aks-multinic.XXXXXX")
kubeconfig_path="$temporary_directory/kubeconfig"
az_resource aks get-credentials -g "$resource_group" -n "$cluster_name" --file "$(native_path "$kubeconfig_path")" -o none
kubectl_cluster get namespace "$namespace" -o name >/dev/null

verify() {
    kubectl_cluster wait --for=condition=Ready "pod/$pod_name" --namespace "$namespace" "--timeout=${timeout}s" >/dev/null
    local interfaces
    interfaces=$(kubectl_cluster exec --namespace "$namespace" "$pod_name" -- ip -j address show)
    if ! jq -e '
        ([.[] | select(.ifname == "eth0")] | length == 1) and
        any(.[]; .ifname != "lo" and .ifname != "eth0" and any(.addr_info[]; .scope == "global"))
    ' <<< "$interfaces" >/dev/null; then
        die 'Expected CNI eth0 plus an addressed secondary interface. Inspect pod and DRANET events.'
    fi
    jq . <<< "$interfaces"
    kubectl_cluster exec --namespace "$namespace" "$pod_name" -- ip route show
    kubectl_cluster get resourceclaims --namespace "$namespace" -o wide
}
if [[ "$action" == remove-workload ]]; then
    kubectl_cluster delete pod "$pod_name" --namespace "$namespace" --ignore-not-found=true --wait=true "--timeout=${timeout}s"
    kubectl_cluster delete resourceclaimtemplate "$claim_name" --namespace "$namespace" --ignore-not-found=true --wait=true "--timeout=${timeout}s"
    printf 'Workload removed. Namespace, node pool, and Azure resources remain; node costs continue.\n'
    exit 0
fi
if [[ "$action" == verify ]]; then verify; exit 0; fi

if ! jq -e '
    .kubernetesVersion | capture("^(?<major>[0-9]+)\\.(?<minor>[0-9]+)(\\.[0-9]+)?$") |
    ((.major | tonumber) > 1 or ((.major | tonumber) == 1 and (.minor | tonumber) >= 35))
' <<< "$cluster_json" >/dev/null; then
    die 'The public AKS configuration guide requires Kubernetes 1.35 or later.'
fi
[[ $(jq -r '.networkProfile.networkPlugin' <<< "$cluster_json") == azure ]] || die 'AKS-managed Azure CNI is required.'
extension_json=$("${az_command[@]}" extension show --name aks-preview --only-show-errors -o json)
jq -e '.version | type == "string" and length > 0' <<< "$extension_json" >/dev/null || die 'Install or update aks-preview first.'
help_text=$("${az_command[@]}" aks nodepool add --help)
[[ "$help_text" == *--secondary-network-interfaces* ]] || die 'Update aks-preview to expose --secondary-network-interfaces.'
feature_state=$(az_resource feature show --namespace Microsoft.ContainerService --name NetworkingMultiNICPreview --query properties.state -o tsv)
[[ "$feature_state" == Registered ]] || die 'Register NetworkingMultiNICPreview, wait for Registered, and refresh the provider.'
provider_state=$(az_resource provider show --namespace Microsoft.ContainerService --query registrationState -o tsv)
[[ "$provider_state" == Registered ]] || die 'Wait for Microsoft.ContainerService provider registration.'
pools_json=$(az_resource aks nodepool list -g "$resource_group" --cluster-name "$cluster_name" -o json)
if jq -e --arg pool "$node_pool" 'any(.[]; .name == $pool)' <<< "$pools_json" >/dev/null; then
    die 'nodePoolName already exists; deploy requires a new pool. Use verify for an existing deployment.'
fi
primary_subnet=$(jq -er '[.[] | .vnetSubnetId | select(type == "string" and length > 0)][0]' <<< "$pools_json")
primary_vnet=$(printf '%s' "${primary_subnet%/subnets/*}" | tr '[:upper:]' '[:lower:]')
[[ "$primary_vnet" == "$secondary_vnet" ]] || die 'Secondary subnets must belong to the same VNet as the primary NICs.'
while IFS= read -r subnet; do
    az_resource network vnet subnet show --ids "$subnet" -o none
done <<< "$subnet_list"
location=$(jq -er '.location' <<< "$cluster_json")
skus_json=$(az_resource vm list-skus --location "$location" --resource-type virtualMachines --size "$vm_size" --all -o json)
sku_json=$(jq -ce --arg size "$vm_size" '
    [.[] | select(.name == $size)] |
    if length == 1 then .[0] else error("VM size not found uniquely in cluster region") end
' <<< "$skus_json")
max_nics=$(jq -er '
    [.capabilities[] | select(.name == "MaxNetworkInterfaces") | .value | tonumber] |
    if length == 1 then .[0] else error("Missing NIC capacity") end
' <<< "$sku_json")
(( max_nics >= 1 + nic_count )) || die 'VM size must support one primary NIC plus every secondary NIC.'
if jq -e 'any(.restrictions[]; .type == "Location")' <<< "$sku_json" >/dev/null; then
    die 'The VM size has a location restriction for this subscription.'
fi
existing=$(kubectl_cluster get pod "$pod_name" --namespace "$namespace" --ignore-not-found=true -o name)
[[ -z "$existing" ]] || die 'The configured pod already exists; choose a new name.'
existing=$(kubectl_cluster get resourceclaimtemplate "$claim_name" --namespace "$namespace" --ignore-not-found=true -o name)
[[ -z "$existing" ]] || die 'The configured claim template already exists; choose a new name.'

render
az_resource aks nodepool add -g "$resource_group" --cluster-name "$cluster_name" --name "$node_pool" \
    --mode User --os-type Linux --node-vm-size "$vm_size" --node-count "$node_count" \
    --vnet-subnet-id "$primary_subnet" --secondary-network-interfaces "@$(native_path "$nic_path")" -o json
deadline=$(( $(date +%s) + timeout ))
while true; do
    device_class=$(kubectl_cluster get deviceclass standard-secondary-nic --ignore-not-found=true -o name)
    [[ -z "$device_class" ]] || break
    (( $(date +%s) < deadline )) || die 'Timed out waiting for the DRANET DeviceClass. The new pool remains billable.'
    sleep 5
done
kubectl_cluster get daemonset -A
kubectl_cluster apply -f "$(native_path "$manifest_path")"
verify
