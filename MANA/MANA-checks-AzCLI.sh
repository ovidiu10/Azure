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
#
# IMPORTANT: After the LegacyVMNVA tag is placed on the VM/VMSS, use
# 'reapply' as the PREFERRED way to make Azure honor it - it re-evaluates
# placement WITHOUT downtime. A stop-deallocate + start is a LAST RESORT
# only (use it if reapply does not take effect); it incurs downtime and a
# full re-placement.
# ---------------------------------------------------------------------
# PREFERRED - Standalone VM or VMSS Flex instance:
# az vm reapply --resource-group "$RG" --name "$VM"
#
# PREFERRED - VMSS Uniform:
# az rest --method post \
#   --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Compute/virtualMachineScaleSets/$VMSS/reapply?api-version=2025-11-01"
#
# LAST RESORT ONLY (incurs downtime) - if reapply does not take effect:
# az vm deallocate -g "$RG" -n "$VM" && az vm start -g "$RG" -n "$VM"

# ---------------------------------------------------------------------
# 3. IN-GUEST (LINUX) - run these INSIDE the Linux VM
# ---------------------------------------------------------------------
# ---------------------------------------------------------------------
# IMPORTANT: These in-guest checks (Linux OR Windows) can legitimately
# return EMPTY / "not found" - e.g. when the VM currently sits on
# previous-gen (Mellanox) hardware, or is on MANA hardware without
# Accelerated Networking enabled. An empty result does NOT mean the VM
# is broken. What actually matters is that the MANA DRIVER is present in
# the OS, so that whenever the VM lands on MANA-capable hardware it can
# use the accelerated path instead of falling back to NetVSC. Validate
# driver presence (mana*.ko for the running kernel), not just whether a
# device currently shows up in lspci/ip link.
# ---------------------------------------------------------------------
# Identify the MANA PCI device (Microsoft Corporation Device 00ba):
# DEVICE check - is the MANA PCI VF exposed RIGHT NOW (device 00ba)?
# NOTE: returns NOTHING when the VM is on Mellanox (previous-gen) hardware -
#       that is EXPECTED, not a failure. On Mellanox you will instead see a
#       ConnectX VF (mlx5_core) bonded to eth0, which is still Accelerated
#       Networking - just not MANA. The 00ba VF only appears once Azure
#       places the VM on MANA-capable hardware.
#   lspci | grep -i "00ba"
#   lspci -d 1414:            # any Microsoft (MANA) PCI device
#   lspci -d 15b3:            # any Mellanox VF (ConnectX) - AN on non-MANA HW
#
# DRIVER check - IS THE MANA DRIVER PRESENT IN THE OS? (the check that
# actually matters - present even when no MANA device exists yet):
#   grep -q 'mana' /lib/modules/$(uname -r)/modules.builtin && echo "MANA built into kernel"
#   find /lib/modules/$(uname -r)/kernel -name 'mana*.ko*' 2>/dev/null
#   # Output present -> driver is staged; it binds automatically on MANA HW
#   #                   (it will NOT be loaded/bound while on Mellanox - normal).
#
# Each AccelNet vNIC => two interfaces (synthetic eth0 + bonded VF enP*):
#   ip link
#
# Which driver actually drives each interface (hv_netvsc synthetic vs
# mlx5_core = Mellanox VF vs mana = MANA VF):
#   for i in $(ls /sys/class/net); do echo -n "$i: "; ethtool -i $i 2>/dev/null | grep driver; done
#
# Confirm traffic flows through the VF (counters must increment):
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
