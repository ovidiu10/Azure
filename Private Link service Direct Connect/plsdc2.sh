#cSpell:disable
#!/usr/bin/env bash
set -euo pipefail

#############################################
# Variables (edit as needed)
#############################################
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

# Pick a supported preview region from the doc
# (e.g., westus2, westus3, eastus2, centralus, southcentralus, etc.)  [1](https://learn.microsoft.com/en-us/azure/private-link/configure-private-link-service-direct-connect)
LOC="westus2"

# Provider (service) side
RG_PROV="rg-plsdc-prov"
VNET_PROV="vnet-egw-prov"
SUBNET_VMSS="snet-vmss"
SUBNET_PLS="snet-pls-nat"

VNET_PROV_PREFIX="10.20.0.0/16"
SUBNET_VMSS_PREFIX="10.20.1.0/24"
SUBNET_PLS_PREFIX="10.20.2.0/24"

LB_NAME="ilb-egw"
LB_FE_NAME="fe-ilb-egw"
LB_BE_NAME="be-vmss"
LB_PROBE_NAME="hp-443"
LB_RULE_NAME="lbr-443"

# IMPORTANT: ILB FE IP must be STATIC and within SUBNET_VMSS_PREFIX
ILB_FE_IP="10.20.1.10"

VMSS_NAME="vmss-egw"
VMSS_INSTANCES=2
ADMIN_USER="azureuser"

# PLS Direct Connect
PLS_NAME="pls-egw-directconnect"
# Minimum 2 NAT IP configurations required (or multiples of 2; max 8)  [1](https://learn.microsoft.com/en-us/azure/private-link/configure-private-link-service-direct-connect)
PLS_NAT_IP1="10.20.2.10"
PLS_NAT_IP2="10.20.2.11"

# Consumer (client) side
RG_CONS="rg-plsdc-cons"
VNET_CONS="vnet-cust"
SUBNET_PE="snet-pe"
VNET_CONS_PREFIX="10.30.0.0/16"
SUBNET_PE_PREFIX="10.30.1.0/24"

PE_NAME="pe-to-plsdc"
PE_CONN_NAME="conn-to-plsdc"

#############################################
# 0) Subscription + feature flag prereq
#############################################
echo "==> Using subscription: ${SUBSCRIPTION_ID}"
az account set --subscription "${SUBSCRIPTION_ID}"

# Register the preview feature flag required by the doc  [1](https://learn.microsoft.com/en-us/azure/private-link/configure-private-link-service-direct-connect)
echo "==> Registering feature: Microsoft.Network/AllowPrivateLinkserviceUDR (required for PLS Direct Connect)"
az feature register --namespace Microsoft.Network --name AllowPrivateLinkserviceUDR 1>/dev/null || true

echo "==> Ensuring Microsoft.Network provider is registered"
az provider register --namespace Microsoft.Network 1>/dev/null || true

echo "NOTE: Feature registration can take time. Check status with:"
echo "  az feature show --namespace Microsoft.Network --name AllowPrivateLinkserviceUDR -o table"
echo

#############################################
# 1) Provider side: RG + VNet + Subnets
#############################################
echo "==> Creating provider resource group + VNet/subnets"
az group create -n "${RG_PROV}" -l "${LOC}" 1>/dev/null

az network vnet create \
  -g "${RG_PROV}" \
  -n "${VNET_PROV}" \
  --address-prefixes "${VNET_PROV_PREFIX}" \
  --subnet-name "${SUBNET_VMSS}" \
  --subnet-prefixes "${SUBNET_VMSS_PREFIX}" \
  1>/dev/null

az network vnet subnet create \
  -g "${RG_PROV}" \
  --vnet-name "${VNET_PROV}" \
  -n "${SUBNET_PLS}" \
  --address-prefixes "${SUBNET_PLS_PREFIX}" \
  1>/dev/null

# Disable privateLinkServiceNetworkPolicies on the PLS NAT subnet as required  [1](https://learn.microsoft.com/en-us/azure/private-link/configure-private-link-service-direct-connect)
echo "==> Disabling Private Link Service network policies on ${SUBNET_PLS}"
az network vnet subnet update \
  -g "${RG_PROV}" \
  --vnet-name "${VNET_PROV}" \
  -n "${SUBNET_PLS}" \
  --private-link-service-network-policies Disabled \
  1>/dev/null

#############################################
# 2) Provider side: Internal Standard LB + backend pool
#############################################
echo "==> Creating internal Standard Load Balancer with static frontend IP ${ILB_FE_IP}"
az network lb create \
  -g "${RG_PROV}" \
  -n "${LB_NAME}" \
  --sku Standard \
  --vnet-name "${VNET_PROV}" \
  --subnet "${SUBNET_VMSS}" \
  --frontend-ip-name "${LB_FE_NAME}" \
  --private-ip-address "${ILB_FE_IP}" \
  1>/dev/null

echo "==> Creating LB backend pool"
az network lb address-pool create \
  -g "${RG_PROV}" \
  --lb-name "${LB_NAME}" \
  -n "${LB_BE_NAME}" \
  1>/dev/null

echo "==> Creating LB health probe and rule (443)"
az network lb probe create \
  -g "${RG_PROV}" \
  --lb-name "${LB_NAME}" \
  -n "${LB_PROBE_NAME}" \
  --protocol Tcp \
  --port 443 \
  1>/dev/null

az network lb rule create \
  -g "${RG_PROV}" \
  --lb-name "${LB_NAME}" \
  -n "${LB_RULE_NAME}" \
  --protocol Tcp \
  --frontend-ip-name "${LB_FE_NAME}" \
  --backend-pool-name "${LB_BE_NAME}" \
  --probe-name "${LB_PROBE_NAME}" \
  --frontend-port 443 \
  --backend-port 443 \
  1>/dev/null

#############################################
# 3) Provider side: VMSS attached to ILB backend pool
#############################################
echo "==> Creating VMSS (${VMSS_INSTANCES} instances) and attaching to ILB backend pool"
az vmss create \
  -g "${RG_PROV}" \
  -n "${VMSS_NAME}" \
  -l "${LOC}" \
  --image Ubuntu2204 \
  --instance-count "${VMSS_INSTANCES}" \
  --upgrade-policy-mode automatic \
  --admin-username "${ADMIN_USER}" \
  --generate-ssh-keys \
  --vnet-name "${VNET_PROV}" \
  --subnet "${SUBNET_VMSS}" \
  --lb "${LB_NAME}" \
  --backend-pool-name "${LB_BE_NAME}" \
  1>/dev/null

#############################################
# 4) Provider side: Create PLS Direct Connect (destination IP = ILB FE IP)
#############################################
echo "==> Creating PLS Direct Connect with destination IP = ${ILB_FE_IP}"
PLS_SUBNET_ID="$(az network vnet subnet show -g "${RG_PROV}" --vnet-name "${VNET_PROV}" -n "${SUBNET_PLS}" --query id -o tsv)"

# PLS Direct Connect requires:
# - destination IP address (static, reachable in VNet)  [1](https://learn.microsoft.com/en-us/azure/private-link/configure-private-link-service-direct-connect)
# - minimum 2 NAT ip configurations (or multiples of 2) [1](https://learn.microsoft.com/en-us/azure/private-link/configure-private-link-service-direct-connect)
az network private-link-service create \
  -g "${RG_PROV}" \
  -n "${PLS_NAME}" \
  -l "${LOC}" \
  --destination-ip-address "${ILB_FE_IP}" \
  --ip-configurations "[
    {
      \"name\": \"ipconfig1\",
      \"primary\": true,
      \"privateIpAllocationMethod\": \"Static\",
      \"privateIpAddress\": \"${PLS_NAT_IP1}\",
      \"subnet\": { \"id\": \"${PLS_SUBNET_ID}\" }
    },
    {
      \"name\": \"ipconfig2\",
      \"primary\": false,
      \"privateIpAllocationMethod\": \"Static\",
      \"privateIpAddress\": \"${PLS_NAT_IP2}\",
      \"subnet\": { \"id\": \"${PLS_SUBNET_ID}\" }
    }
  ]" \
  1>/dev/null

PLS_ID="$(az network private-link-service show -g "${RG_PROV}" -n "${PLS_NAME}" --query id -o tsv)"
PLS_ALIAS="$(az network private-link-service show -g "${RG_PROV}" -n "${PLS_NAME}" --query alias -o tsv)"

echo "==> PLS Direct Connect created:"
echo "    Resource ID : ${PLS_ID}"
echo "    Alias       : ${PLS_ALIAS}"
echo

#############################################
# 5) Consumer side: RG + VNet/subnet + Private Endpoint to PLS
#############################################
echo "==> Creating consumer resource group + VNet/subnet"
az group create -n "${RG_CONS}" -l "${LOC}" 1>/dev/null

az network vnet create \
  -g "${RG_CONS}" \
  -n "${VNET_CONS}" \
  --address-prefixes "${VNET_CONS_PREFIX}" \
  --subnet-name "${SUBNET_PE}" \
  --subnet-prefixes "${SUBNET_PE_PREFIX}" \
  1>/dev/null

# Disable Private Endpoint network policies on the PE subnet (needed for PE) [1](https://learn.microsoft.com/en-us/azure/private-link/configure-private-link-service-direct-connect)
echo "==> Disabling Private Endpoint network policies on ${SUBNET_PE}"
az network vnet subnet update \
  -g "${RG_CONS}" \
  --vnet-name "${VNET_CONS}" \
  -n "${SUBNET_PE}" \
  --private-endpoint-network-policies Disabled \
  1>/dev/null

echo "==> Creating Private Endpoint to PLS Direct Connect"
az network private-endpoint create \
  -g "${RG_CONS}" \
  -n "${PE_NAME}" \
  -l "${LOC}" \
  --vnet-name "${VNET_CONS}" \
  --subnet "${SUBNET_PE}" \
  --private-connection-resource-id "${PLS_ID}" \
  --connection-name "${PE_CONN_NAME}" \
  1>/dev/null

echo
echo "==> NOTE: The PLS owner must approve the private endpoint connection (unless you configured auto-approval in your org)."
echo "    You can view pending connections on the provider side as shown below."
echo

#############################################
# 6) Verify (provider + consumer)
#############################################
echo "==> Provider verification (destination IP + ip config count)"
az network private-link-service show \
  -g "${RG_PROV}" \
  -n "${PLS_NAME}" \
  --query "{name:name, provisioningState:provisioningState, destinationIpAddress:destinationIpAddress, ipConfigCount:length(ipConfigurations)}" \
  -o jsonc

echo
echo "==> Provider: list private endpoint connection statuses"
az network private-link-service show \
  -g "${RG_PROV}" \
  -n "${PLS_NAME}" \
  --query "privateEndpointConnections[].{name:name, status:privateLinkServiceConnectionState.status, description:privateLinkServiceConnectionState.description}" \
  -o table

echo
echo "==> Consumer: show Private Endpoint NIC private IP (PE-side IP)"
PE_NIC_ID="$(az network private-endpoint show -g "${RG_CONS}" -n "${PE_NAME}" --query 'networkInterfaces[0].id' -o tsv)"
az network nic show --ids "${PE_NIC_ID}" --query "ipConfigurations[0].privateIpAddress" -o tsv | sed 's/^/PE private IP: /'

echo
echo "DONE."
echo
echo "Optional approval command (run on provider side AFTER you identify the connection name):"
echo "  az network private-endpoint-connection approve \\"
echo "    -g ${RG_PROV} \\"
echo "    --resource-name ${PLS_NAME} \\"
echo "    --type Microsoft.Network/privateLinkServices \\"
echo "    -n <privateEndpointConnectionName> \\"
echo "    --description 'Approved'"
echo
echo "Cleanup:"
echo "  az group delete -n ${RG_CONS} --yes --no-wait"
echo "  az group delete -n ${RG_PROV} --yes --no-wait"