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
#
# IMPORTANT: After the LegacyVMNVA tag is placed on the VM/VMSS, use
# 'reapply' as the PREFERRED way to make Azure honor it - it re-evaluates
# placement WITHOUT downtime. A stop-deallocate + start is a LAST RESORT
# only (use it if reapply does not take effect); it incurs downtime and a
# full re-placement.
# =====================================================================
# PREFERRED - Standalone VM or VMSS Flex instance:
# Invoke-AzResourceAction -ResourceGroupName $ResourceGroup `
#     -ResourceType "Microsoft.Compute/virtualMachines" `
#     -ResourceName $VmName -Action "reapply" -Force

# PREFERRED - VMSS Uniform:
# Invoke-AzRestMethod -Method POST `
#     -Path "/subscriptions/<subscription-id>/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/<vmss-name>/reapply?api-version=2025-11-01"

# LAST RESORT ONLY (incurs downtime) - if reapply does not take effect:
# Stop-AzVM  -ResourceGroupName $ResourceGroup -Name $VmName -Force   # full deallocate
# Start-AzVM -ResourceGroupName $ResourceGroup -Name $VmName

# =====================================================================
# 3. IN-GUEST (WINDOWS) - run these INSIDE the Windows VM
# =====================================================================
# ---------------------------------------------------------------------
# IMPORTANT: These in-guest checks (Windows OR Linux) can legitimately
# return EMPTY / "not found" - e.g. when the VM currently sits on
# previous-gen (Mellanox) hardware, or is on MANA hardware without
# Accelerated Networking enabled. An empty result does NOT mean the VM
# is broken. What actually matters is that the MANA DRIVER is present in
# the OS, so that whenever the VM lands on MANA-capable hardware it can
# use the accelerated path instead of falling back to NetVSC. Validate
# driver presence, not just whether a device currently shows up.
# ---------------------------------------------------------------------
# List adapters - look for "Microsoft Azure Network Adapter"
#   Get-NetAdapter
#
# DEVICE check - is the MANA PCI VF exposed RIGHT NOW (VEN_1414 DEV_00BA)?
# NOTE: this returns NOTHING when the VM is on Mellanox (previous-gen)
#       hardware - that is EXPECTED, not a failure. It only appears once
#       Azure places the VM on MANA-capable hardware.
#   Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match '^PCI\\VEN_1414&DEV_00BA&' }
#
# DRIVER-STORE check - IS THE MANA DRIVER STAGED IN THE OS? (the check that
# actually matters - present even when no MANA device exists yet)
#   pnputil /enum-drivers | Select-String -Context 0,5 'mana'
#   Get-WindowsDriver -Online -All |
#       Where-Object { $_.OriginalFileName -match 'mana' -or $_.Driver -match 'mana' } |
#       Format-Table Driver, OriginalFileName, ProviderName, Version, ClassName
#   # Output present  -> MANA driver installed; binds automatically on MANA hardware.
#   # Output empty    -> driver not in image; use a MANA-supported image/driver.
#
# Confirm traffic is actually flowing through the MANA VF (counters must increment):
#   Get-NetAdapter | Where-Object InterfaceDescription -Like "*Microsoft Azure Network Adapter*" |
#       Get-NetAdapterStatistics
#
# If the PCI device is present but no MANA adapter shows, install drivers:
#   https://aka.ms/manawindowsdrivers

# =====================================================================
# 4. Push the IN-GUEST DRIVER-PRESENCE check remotely via Run Command
#    (driver-store check only - independent of current hardware placement)
#
# HOW THIS WORKS (two separate layers - do not confuse them):
#   * Invoke-AzVMRunCommand is an Az PowerShell cmdlet that runs on YOUR
#     workstation (the control plane). It does NOT require PowerShell on
#     the target VM.
#   * -CommandId selects the interpreter Azure's guest agent uses INSIDE
#     the VM: 'RunShellScript' = bash (Linux), 'RunPowerShellScript' =
#     PowerShell (Windows).
#   => The Linux target below runs a BASH script in the guest even though
#      you launch it from a PowerShell cmdlet. Linux never runs PowerShell.
# =====================================================================
# Windows target - is the MANA driver staged in the driver store?
# Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VmName `
#     -CommandId 'RunPowerShellScript' `
#     -ScriptString 'pnputil /enum-drivers | Select-String -Context 0,5 "mana"; Get-WindowsDriver -Online -All | Where-Object { $_.OriginalFileName -match "mana" -or $_.Driver -match "mana" } | Format-Table Driver, OriginalFileName, ProviderName, Version, ClassName'

# Linux target - is the MANA driver present (built-in or as a module)?
# (RunShellScript => bash runs in the guest; not PowerShell)
# Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VmName `
#     -CommandId 'RunShellScript' `
#     -ScriptString 'grep -q "mana" /lib/modules/$(uname -r)/modules.builtin && echo "MANA built into kernel"; find /lib/modules/$(uname -r)/kernel -name "mana*.ko*" 2>/dev/null'
