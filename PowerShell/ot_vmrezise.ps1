$vm = Get-AzVM -ResourceGroupName rg-netcore11 -Name vmoldsku
Stop-AzVM -ResourceGroupName rg-netcore11 -Name vmoldsku
Get-AzVM -ResourceGroupName rg-netcore11 -Name vmoldsku -Status
$vm.HardwareProfile.VmSize = "Standard_D16ds_v4"
Update-AzVM -ResourceGroupName rg-netcore11 -VM $vm
Start-AzVM -Name vmoldsku -ResourceGroupName rg-netcore11