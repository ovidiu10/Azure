#!/usr/bin/env bash
# Offline integration checks with exported az/kubectl mocks; Bash and jq only.
set -euo pipefail
directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/aks-multinic-tests.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT
config_path="$temporary/config.json"
export MOCK_LOG="$temporary/tool-calls" MOCK_CREDENTIALS="$temporary/credential-paths"
export MOCK_MODE=normal
original_ostype=${OSTYPE:-}
if real_cygpath=$(command -v cygpath); then export MOCK_REAL_CYGPATH=$real_cygpath; else export MOCK_REAL_CYGPATH=; fi
export MOCK_VNET='/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-group/providers/Microsoft.Network/virtualNetworks/test-vnet'
base_config=$(jq --arg vnet "$MOCK_VNET" '
    .subscriptionId = "00000000-0000-0000-0000-000000000000" |
    .resourceGroup = "test-group" | .clusterName = "test-cluster" |
    .nodePoolName = "nicpool" | .namespace = "test-namespace" |
    .podName = "test-pod" | .claimTemplateName = "test-claim" |
    .vmSize = "Standard_D8s_v5" | .image = "nicolaka/netshoot:v0.14" |
    .secondarySubnetIds = [($vnet + "/subnets/secondary")]
' "$directory/../shared/config.example.json")
printf '%s\n' "$base_config" > "$config_path"
: > "$MOCK_LOG"
: > "$MOCK_CREDENTIALS"

az() {
    if [[ "${OSTYPE:-}" == msys ]]; then
        [[ "${MSYS_NO_PATHCONV:-}" == 1 && "${MSYS2_ARG_CONV_EXCL:-}" == '*' ]] || return 97
    fi
    printf 'az ' >> "$MOCK_LOG"; printf '%q ' "$@" >> "$MOCK_LOG"; printf '\n' >> "$MOCK_LOG"
    if [[ "$MOCK_MODE" == native-failure ]]; then return 7; fi
    case "$1 $2" in
        'aks show')
            if [[ "$MOCK_MODE" == old-version ]]; then
                printf '{"kubernetesVersion":"1.34.9","location":"eastus","networkProfile":{"networkPlugin":"azure"}}\r\n'
            else
                printf '{"kubernetesVersion":"1.35.2","location":"eastus","networkProfile":{"networkPlugin":"azure"}}\r\n'
            fi ;;
        'aks get-credentials')
            while [[ $# -gt 0 ]]; do
                if [[ "$1" == --file ]]; then
                    printf '%s\n' "$2" >> "$MOCK_CREDENTIALS"
                    printf 'temporary credentials\n' > "$2"
                    break
                fi
                shift
            done ;;
        'extension show') printf '{"version":"1.0"}\r\n' ;;
        'feature show')
            if [[ "$MOCK_MODE" == registering ]]; then printf 'Registering\r\n'; else printf 'Registered\r\n'; fi ;;
        'provider show') printf 'Registered\r\n' ;;
        'network vnet') : ;;
        'vm list-skus')
            if [[ "$MOCK_MODE" == insufficient-nics ]]; then max_nics=1; else max_nics=4; fi
            printf '[{"name":"Standard_D8s_v5","capabilities":[{"name":"MaxNetworkInterfaces","value":"%s"}],"restrictions":[]}]\r\n' "$max_nics" ;;
        'aks nodepool')
            if [[ "$3" == list ]]; then
                if [[ "$MOCK_MODE" == existing-pool ]]; then pool=nicpool; else pool=system; fi
                printf '[{"name":"%s","vnetSubnetId":"%s/subnets/primary"}]\r\n' "$pool" "$MOCK_VNET"
            elif [[ " $* " == *' --help '* ]]; then
                printf '%s\n' '--secondary-network-interfaces'
            elif [[ "$3" == add ]]; then
                printf '{"provisioningState":"Succeeded"}\r\n'
            else return 99; fi ;;
        *) printf 'Unexpected mock az command\n' >&2; return 99 ;;
    esac
}
kubectl() {
    printf 'kubectl ' >> "$MOCK_LOG"; printf '%q ' "$@" >> "$MOCK_LOG"; printf '\n' >> "$MOCK_LOG"
    [[ "$1" == --kubeconfig && -f "$2" ]] || return 98
    shift 2
    case "$1" in
        get)
            case "$2" in
                namespace) printf 'namespace/test-namespace\r\n' ;;
                pod) if [[ "$MOCK_MODE" == existing-pod ]]; then printf 'pod/test-pod\r\n'; fi ;;
                resourceclaimtemplate) : ;;
                deviceclass) printf 'deviceclass/standard-secondary-nic\r\n' ;;
                daemonset) printf 'managed-driver-ready\r\n' ;;
                resourceclaims) printf 'allocated\r\n' ;;
                *) return 99 ;;
            esac ;;
        wait|delete) : ;;
        apply) [[ -f "$3" ]] || return 98; printf 'configured\r\n' ;;
        exec)
            if [[ " $* " == *' ip -j address show '* ]]; then
                if [[ "$MOCK_MODE" == no-secondary ]]; then scope=link; else scope=global; fi
                printf '[{"ifname":"eth0","addr_info":[{"scope":"global"}]},{"ifname":"net1","addr_info":[{"scope":"%s"}]}]\r\n' "$scope"
            else printf 'secondary subnet route\r\n'; fi ;;
        *) return 99 ;;
    esac
}
export -f az kubectl
cygpath() {
    printf '%s %s\n' "$1" "$2" >> "$MOCK_PATHS"
    if [[ -n "$MOCK_REAL_CYGPATH" ]]; then "$MOCK_REAL_CYGPATH" "$@"; else printf '%s\n' "$2"; fi
}
run_sample() {
    bash "$directory/aks-multinic.sh" "$@" --config "$config_path" \
        --output-dir "$temporary/output with spaces" > "$temporary/stdout" 2> "$temporary/stderr"
}
expect_failure() {
    if run_sample "$@"; then
        printf 'Expected failure: %s\n' "$*" >&2
        exit 1
    fi
}
assert_no_pool() {
    if grep -q -- '--mode User' "$MOCK_LOG"; then printf 'Unexpected node pool creation\n' >&2; exit 1; fi
}
assert_no_credentials() {
    while IFS= read -r path; do
        [[ ! -f "$path" ]] || { printf 'Credential file was not removed\n' >&2; exit 1; }
    done < "$MOCK_CREDENTIALS"
}

bash -n "$directory/aks-multinic.sh"
run_sample render
[[ ! -s "$MOCK_LOG" ]]
jq -e --arg vnet "$MOCK_VNET" 'length == 1 and .[0].vnetSubnetId == ($vnet + "/subnets/secondary")' \
    "$temporary/output with spaces/secondary-nics.json" >/dev/null
jq -e '
    .items[0].metadata.name == .items[1].spec.resourceClaims[0].resourceClaimTemplateName and
    .items[1].spec.nodeSelector["kubernetes.azure.com/agentpool"] == "nicpool" and
    .items[0].spec.spec.devices.requests[0].exactly.count == 1
' "$temporary/output with spaces/workload.json" >/dev/null
rm -rf -- "$temporary/output with spaces"
for action in render deploy verify remove-workload; do
    run_sample "$action" --dry-run
    [[ ! -d "$temporary/output with spaces" && ! -s "$MOCK_LOG" ]]
done
expect_failure deploy
[[ ! -s "$MOCK_LOG" ]]

run_sample deploy --yes
grep -q -- '--mode User --os-type Linux' "$MOCK_LOG"
grep -q -- '--subscription 00000000-0000-0000-0000-000000000000' "$MOCK_LOG"
if grep '^az ' "$MOCK_LOG" | grep -vE '^az extension|--help' | grep -v -- '--subscription' >/dev/null; then
    printf 'An Azure resource command was not subscription-scoped\n' >&2
    exit 1
fi
run_sample verify
assert_no_credentials

# Exercise Git Bash's path/argument guards with local cygpath and native-tool mocks.
export MOCK_PATHS="$temporary/path-conversions"
export -f cygpath
export OSTYPE=msys
run_sample deploy --yes
grep -q -- '-u ' "$MOCK_PATHS"
grep -q -- '-am ' "$MOCK_PATHS"
assert_no_credentials
export OSTYPE=$original_ostype

for mode in old-version registering insufficient-nics existing-pool existing-pod native-failure; do
    export MOCK_MODE=$mode
    : > "$MOCK_LOG"
    expect_failure deploy --yes
    assert_no_pool
    assert_no_credentials
done
export MOCK_MODE=no-secondary
expect_failure verify
export MOCK_MODE=normal
: > "$MOCK_LOG"
run_sample remove-workload --yes
[[ $(grep -c ' delete ' "$MOCK_LOG") == 2 ]]
grep -q 'delete pod test-pod' "$MOCK_LOG"
grep -q 'delete resourceclaimtemplate test-claim' "$MOCK_LOG"
if grep '^az .*delete' "$MOCK_LOG" >/dev/null; then printf 'Azure cleanup was unexpectedly called\n' >&2; exit 1; fi
assert_no_credentials

printf '%s\n' "$base_config" | jq '.secondarySubnetIds += .secondarySubnetIds' > "$config_path"
run_sample render
jq -e 'length == 2' "$temporary/output with spaces/secondary-nics.json" >/dev/null
printf '%s\n' "$base_config" | jq '.nodeCount = true' > "$config_path"
expect_failure render
printf '%s\n' "$base_config" | jq '.image = "image@sha256:invalid"' > "$config_path"
expect_failure render
printf '%s\n' "$base_config" | jq '.secondarySubnetIds += [(.secondarySubnetIds[0] | sub("test-vnet"; "other-vnet"))]' > "$config_path"
expect_failure render
cp "$directory/../shared/config.example.json" "$config_path"
expect_failure render
printf 'PASS: Bash syntax, offline rendering/dry-run, CRLF handling, CLI wiring, lifecycle, errors, and cleanup.\n'
