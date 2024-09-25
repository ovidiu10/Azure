Connect-AzAccount -Subscription "your subscription id"
$vm = Get-AzVM -ResourceGroupName "your resource group" -Name "your vm name"
Remove-AzVMDataDisk -VM $vm -Name "your disk name"
$vm.StorageProfile.DataDisks | ft

Update-AzVM -ResourceGroupName "your resource group" -VM $vm
Invoke-AzVMRunCommand -ResourceGroupName "your resource group" -Name $vm.Name  -CommandId "RunPowerShellScript" -ScriptString "Resize-Partition -DriveLetter <your volume drive leter> -Size (Get-PartitionSupportedSize -DriveLetter <your volume drive leter>).SizeMax"
Invoke-AzVMRunCommand -ResourceGroupName "your resource group" -Name $vm.Name -CommandId "RunPowerShellScript" -ScriptString "get-disk | format-list number, path"
