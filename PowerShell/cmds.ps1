
Write-Host "WARNING: Please ensure that you have at least PowerShell 7 before running this script. Visit https://go.microsoft.com/fwlink/?linkid=2181071 for the procedure." -ForegroundColor Yellow
$RSmodule = Get-Module -Name Az.RecoveryServices -ListAvailable
$NWmodule = Get-Module -Name Az.Network -ListAvailable
$RSversion = $RSmodule.Version.ToString()
$NWversion = $NWmodule.Version.ToString()

$rg = ""
$vmName = ""
$vm = Get-AzVM -ResourceGroupName $rg -Name $vmName
#get private IP address
Get-AzNetworkInterface -ResourceGroupName $rg | where {$_.VirtualMachine.Id -eq $vm.id} |  Select-Object -Property @{n="Name"; e={ $_.VirtualMachine.Id.Split("/")[-1] }}, @{n="PrivateIPAddress"; e= { $_.IpConfigurations.PrivateIPAddress }}

Set-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -enabled True


get-disk | format-list number, path
Invoke-AzVMRunCommand -ResourceGroupName '<myResourceGroup>' -Name '<myVMName>' -CommandId 'RunPowerShellScript' -ScriptPath '<pathToScript>' -Parameter @{"arg1" = "var1";"arg2" = "var2"}
$vm = Get-AzVM -ResourceGroupName myResourceGroup -Name myVM
$vm.StorageProfile.DataDisks | ft

#https://learn.microsoft.com/en-us/azure/virtual-machines/windows/azure-to-guest-disk-mapping?tabs=azure-powershell #finding-the-lun-for-the-azure-disks
#https://learn.microsoft.com/en-us/powershell/module/az.compute/invoke-azvmruncommand
#Difference between Action RunCommand and Managed RunCommand
#https://learn.microsoft.com/en-us/azure/virtual-machines/run-command-overview

$vm = Get-AzVM -ResourceGroupName $rg -Name $vmName
Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vmName -CommandId "RunPowerShellScript" -ScriptString "get-disk | format-list number, path"
$vm.StorageProfile.DataDisks | ft
#PowerShell script use in for send over to VM (saved in file ps1):
Get-storagepool | ForEach-Object { if ($_.FriendlyName -ne "Primordial") { "Pool FriendlyName:"+$_.FriendlyName; $_ | Get-PhysicalDisk | Select FriendlyName,PhysicalLocation,AllocatedSize}}
Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vmName -CommandId "RunPowerShellScript" -ScriptPath "s2.ps1"
#Bonus resize of the disk https://learn.microsoft.com/en-us/azure/virtual-machines/windows/expand-os-disk#resize-a-managed-disk-by-using-powershell but is not working for Ultra SSD or Premium SSD v2 without deallocation of VM first ☹ for rest of disk like Premium SSD works without deallocation of VM https://learn.microsoft.com/en-us/azure/virtual-machines/windows/expand-os-disk#expand-without-downtime
#Also no need to RDP in VM you can use same technic like before and resize https://learn.microsoft.com/en-us/windows-server/storage/disk-management/extend-a-basic-volume#extend-a-volume-with-powershell
#https://learn.microsoft.com/en-us/powershell/module/storage/resize-partition?view=windowsserver2016-ps
#sample
$disk3 = get-azdisk -ResourceGroupName $vm -DiskName $vm.StorageProfile.DataDisks[2].Name
$disk3.DiskSizeGB = 1024
Update-AzDisk -ResourceGroupName $rg -Disk $vm -DiskName $disk3.Name
Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vmName -CommandId "RunPowerShellScript" -ScriptString "Resize-Partition -DriveLetter H -Size (Get-PartitionSupportedSize -DriveLetter H).SizeMax"
#enable ICMP in firewall
Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vmName -CommandId "RunPowerShellScript" -ScriptString "Set-NetFirewallRule -DisplayName 'File and Printer Sharing (Echo Request - ICMPv4-In)' -enabled True"

#Run psSDP script on multiple VMs 
Set-AzContext -Subscription "<YourSubscriptionID>"
Get-AzVM -Status 
foreach ($vm in $vms) {
    $result = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -CommandId "RunPowerShellScript" -ScriptString "cd c:\temp\tss\psSDP; .\Get-psSDP.ps1 SQLbase -SkipEULA" 
    Write-Host "VM: $($vm.Name)"
    Write-Host "Command Output: $($result.Value[0].Message)"
}

