Connect-AzAccount -Subscription "your subscription id"
$vm = Get-AzVM -ResourceGroupName "your resource group" -Name "your vm name"
$vm.StorageProfile.DataDisks | ft
Remove-AzVMDataDisk -VM $vm -Name "your disk name"
$vm.StorageProfile.DataDisks | ft

$disk = Get-AzDisk -ResourceGroupName $vm.ResourceGroupName -DiskName "ultra disk name"
New-AzDiskUpdateConfig -DiskSizeGB <value> -DiskIOPSReadWrite <value> | Update-AzDisk -ResourceGroupName $disk.ResourceGroupName -DiskName $disk.Name
Add-AzVMDataDisk -VM $vm -CreateOption Attach -ManagedDiskId $disk.Id -Lun 0
Update-AzVM -ResourceGroupName $vm.ResourceGroupName -VM $vm

Invoke-AzVMRunCommand -ResourceGroupName "your resource group" -Name $vm.Name  -CommandId "RunPowerShellScript" -ScriptString "Resize-Partition -DriveLetter <your volume drive leter> -Size (Get-PartitionSupportedSize -DriveLetter <your volume drive leter>).SizeMax"
Invoke-AzVMRunCommand -ResourceGroupName "your resource group" -Name $vm.Name -CommandId "RunPowerShellScript" -ScriptString "get-disk | format-list number, path"
