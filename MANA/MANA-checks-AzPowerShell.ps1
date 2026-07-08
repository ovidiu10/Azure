<#
.SYNOPSIS
    MANA (Microsoft Azure Network Adapter) readiness checks using Azure PowerShell (Az module)
    plus in-guest verification commands for Windows and Linux VMs.

.NOTES
    Source docs (public):
      - https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-existing-sizes
      - https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-windows
      - https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-linux
      - https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-network-virtual-appliance-opt-out

    Run the CONTROL PLANE section from any workstation with the Az module.
    Run the IN-GUEST WINDOWS section inside a Windows VM.
    Push the IN-GUEST LINUX commands to a Linux VM via Invoke-AzVMRunCommand (shown below).
#>

param(
    [string]$ResourceGroup = "<resource-group-name>",
    [string]$VmName        = "<vm-name>"
)

# =====================================================================
# 0. Connect
# =====================================================================
# Connect-AzAccount
# Set-AzContext -Subscription "<subscription-id>"

# =====================================================================
# 1. CONTROL PLANE - is Accelerated Networking enabled? What size/OS?
# =====================================================================
$vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VmName
"VM size : $($vm.HardwareProfile.VmSize)"
"OS type : $($vm.StorageProfile.OsDisk.OsType)"

# Accelerated Networking status per NIC (AccelNet is required to use the MANA VF)
foreach ($nicRef in $vm.NetworkProfile.NetworkInterfaces) {
    $nic = Get-AzNetworkInterface -ResourceId $nicRef.Id
    "NIC {0} : AcceleratedNetworking = {1}" -f $nic.Name, $nic.EnableAcceleratedNetworking
}

# =====================================================================
# 2. CONTROL PLANE - NVA opt-out (LegacyVMNVA) reapply to enable the tag
#    (only for NVA workloads that degrade on MANA hardware)
# =====================================================================
# Standalone VM or VMSS Flex instance:
# Invoke-AzResourceAction -ResourceGroupName $ResourceGroup `
#     -ResourceType "Microsoft.Compute/virtualMachines" `
#     -ResourceName $VmName -Action "reapply" -Force

# VMSS Uniform:
# Invoke-AzRestMethod -Method POST `
#     -Path "/subscriptions/<subscription-id>/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/<vmss-name>/reapply?api-version=2025-11-01"

# =====================================================================
# 3. IN-GUEST (WINDOWS) - run these INSIDE the Windows VM
# =====================================================================
# List adapters - look for "Microsoft Azure Network Adapter"
#   Get-NetAdapter
#
# Confirm the MANA PCI device is present (VEN_1414 DEV_00BA):
#   Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match '^PCI\\VEN_1414&DEV_00BA&' }
#
# Confirm traffic is actually flowing through the MANA VF (counters must increment):
#   Get-NetAdapter | Where-Object InterfaceDescription -Like "*Microsoft Azure Network Adapter*" |
#       Get-NetAdapterStatistics
#
# If the PCI device is present but no MANA adapter shows, install drivers:
#   https://aka.ms/manawindowsdrivers

# =====================================================================
# 4. Push the IN-GUEST checks remotely via Run Command
# =====================================================================
# Windows target:
# Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VmName `
#     -CommandId 'RunPowerShellScript' `
#     -ScriptString 'Get-NetAdapter; Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match "^PCI\\VEN_1414&DEV_00BA&" }'

# Linux target (run the shell checks through RunShellScript):
# Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VmName `
#     -CommandId 'RunShellScript' `
#     -ScriptString 'lspci | grep -i "00ba"; ip link; ethtool -S eth0 | grep -E "^[ \t]+vf"'
