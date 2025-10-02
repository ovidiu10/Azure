Connect-AzAccount
Select-AzSubscription -Subscription "<YourSubscriptionID>"

$vms = Get-AzVM
foreach ($vm in $vms) {
    $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
    $agentVersion = $vmStatus.VMAgent.VMAgentVersion
    Write-Host "VM: $($vm.Name) | Agent Version: $agentVersion"
    if ($agentVersion -lt "2.7.41491.1172" ) {
        # If agent version is less than the required version, perform some action
        Set-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Reapply
    }
}