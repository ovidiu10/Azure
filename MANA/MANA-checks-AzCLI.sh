#!/usr/bin/env bash
# =====================================================================
# MANA (Microsoft Azure Network Adapter) readiness checks - Azure CLI
# plus in-guest verification commands for Linux and Windows VMs.
#
# Source docs (public):
#   https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-existing-sizes
#   https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-linux
#   https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-windows
#   https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-network-virtual-appliance-opt-out
# =====================================================================

RG="<resource-group-name>"
VM="<vm-name>"
SUB="<subscription-id>"
VMSS="<vmss-name>"

# ---------------------------------------------------------------------
# 0. Sign in
# ---------------------------------------------------------------------
# az login
# az account set --subscription "$SUB"

# ---------------------------------------------------------------------
# 1. CONTROL PLANE - VM size, OS, and Accelerated Networking status
#    (AccelNet is required to use the MANA VF)
# ---------------------------------------------------------------------
az vm show -g "$RG" -n "$VM" --query "{size:hardwareProfile.vmSize, os:storageProfile.osDisk.osType}" -o table

# Accelerated Networking per NIC
for NIC_ID in $(az vm show -g "$RG" -n "$VM" --query "networkProfile.networkInterfaces[].id" -o tsv); do
  az network nic show --ids "$NIC_ID" \
    --query "{nic:name, acceleratedNetworking:enableAcceleratedNetworking}" -o table
done

# ---------------------------------------------------------------------
# 2. CONTROL PLANE - NVA opt-out (LegacyVMNVA): reapply to enable the tag
#    (only for NVA workloads degraded on MANA hardware)
# ---------------------------------------------------------------------
# Standalone VM or VMSS Flex instance:
# az vm reapply --resource-group "$RG" --name "$VM"
#
# VMSS Uniform:
# az rest --method post \
#   --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Compute/virtualMachineScaleSets/$VMSS/reapply?api-version=2025-11-01"

# ---------------------------------------------------------------------
# 3. IN-GUEST (LINUX) - run these INSIDE the Linux VM
# ---------------------------------------------------------------------
# Identify the MANA PCI device (Microsoft Corporation Device 00ba):
#   lspci | grep -i "00ba"
#
# Confirm the MANA Ethernet driver is present:
#   grep /mana*.ko /lib/modules/$(uname -r)/modules.builtin || \
#     find /lib/modules/$(uname -r)/kernel -name 'mana*.ko*'
#
# Each AccelNet vNIC => two interfaces (synthetic eth0 + bonded MANA VF enP*):
#   ip link
#
# Confirm traffic flows through the MANA VF (counters must increment):
#   ethtool -S eth0 | grep -E "^[ \t]+vf"
#
# Kernel note: MANA drivers upstream in 5.15+; 6.2+ adds RDMA/DPDK.

# ---------------------------------------------------------------------
# 4. Push in-guest checks remotely via az vm run-command
# ---------------------------------------------------------------------
# Linux target:
# az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript \
#   --scripts 'lspci | grep -i "00ba"; ip link; ethtool -S eth0 | grep -E "^[ \t]+vf"'

# Windows target (look for "Microsoft Azure Network Adapter" + PCI VEN_1414 DEV_00BA):
# az vm run-command invoke -g "$RG" -n "$VM" --command-id RunPowerShellScript \
#   --scripts "Get-NetAdapter" \
#             "Get-PnpDevice -PresentOnly | Where-Object { \$_.InstanceId -match '^PCI\\\\VEN_1414&DEV_00BA&' }"
