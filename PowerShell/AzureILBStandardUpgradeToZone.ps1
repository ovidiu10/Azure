<#PSScriptInfo
.VERSION 0.6
.TAGS Azure, Az, LoadBalancer, AzNetworking
.changed by Ovi Timpanariu from original https://www.powershellgallery.com/packages/AzureILBUpgrade/5.0 
#>

<#
.DESCRIPTION
This script will help you update a Standard SKU Internal load balancer front end configuration from non zonal to zone redundant.  
.PARAMETER rgName
Name of ResourceGroup of the Standard Internal Load Balancer, like "microsoft_rg1"
.PARAMETER ILBName
Name of Standard Internal Load Balancer you want to upgrade.
.PARAMETER OldFrontEndIPconfigName
Name of FrontendIP Standard Internal Load Balancer which is non zonal.
.PARAMETER NewFrontEndIPconfigName
Name of FrontendIP Standard Internal Load Balancer which is zone redundant.
.EXAMPLE
./AzureILBStandardUpgradeToZone.ps1 -rgName "test_InternalUpgrade_rg" -ILbName "LBForUpgrade" -OldFrontEndIPconfigName "oldFE1" -NewFrontEndIPconfigName "newFE1"
.LINK
https://aka.ms/upgradeloadbalancerdoc
https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-overview/
https://learn.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-availability-zones 
.NOTES
Note - all paramemters are required in order to successfully to update the Standard Internal Load Balancer.
#> 
Param(
[Parameter(Mandatory = $True)][string] $rgName,
#Parameters for new Standard Load Balancer Frontend IP Config Zone redundant 
[Parameter(Mandatory = $True)][string] $ILBName,
[Parameter(Mandatory = $True)][string] $OldFrontEndIPconfigName,
[Parameter(Mandatory = $True)][string] $NewFrontEndIPconfigName
)

#gettincurrent loadbalancer
$lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $ILbName

#1. Backend subnet is always the same as the front end ip config - automatic association
$vnetName = ($lb.FrontendIpConfigurations.subnet.id).Split("/")[8]
$vnetRGName = ($lb.FrontendIpConfigurations.subnet.id).Split("/")[4]
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetRGName
$backendSubnetName = $lb.FrontendIpConfigurations.subnet.id.Split("/")[10]
$backendSubnet = Get-AzVirtualNetworkSubnetConfig -Name $backendSubnetName -VirtualNetwork $vnet
$ipRange = ($backendSubnet.AddressPrefix).split("/")[0]

$frontEndIpConfig = $lb.FrontendIpConfigurations
$newlbFrontendConfigs = $frontEndIpConfig | Where-Object {$_.Name -eq $NewFrontEndIPconfigName}
if ($newlbFrontendConfigs.Count -gt 0) {
    Write-Host "Frontend exist"
    Exit 88
}
$oldlbFrontendConfigs = @()
$oldlbFrontendConfigs = $oldlbFrontendConfigs + ($frontEndIpConfig | Where-Object {$_.Name -eq $OldFrontEndIPconfigName})
if ($oldlbFrontendConfigs.Count -ne 1) {
    Write-Host "Frontend not exist"
    Exit 88
}

[int]$startIp = [int]$ipRange.Split(".")[3] + 1
$startIPTest = $ipRange.Split(".")[0] + "." + $ipRange.Split(".")[1] + "." + $ipRange.Split(".")[2] + "." + $startIp

$availableIPS = (Test-AzPrivateIPAddressAvailability -VirtualNetwork $vnet -IPAddress $startIPTest).AvailableIPAddresses
#$lastAvailableIp = $availableIPS[$availableIPS.count-1]
#initial bit in array to check for available ips

#2. Front Ends
Get-AzLoadBalancerFrontendIpConfig -Name $oldlbFrontendConfigs[0].Name -LoadBalancer $lb
$newFrontEndConfigName = $NewFrontEndIPconfigName
$newSubnetId = $oldlbFrontendConfigs[0].subnet.Id
$ip = $oldlbFrontendConfigs[0].PrivateIpAddress
Add-AzLoadBalancerFrontendIpConfig -Name $newFrontEndConfigName -LoadBalancer $lb -PrivateIpAddress $ip -SubnetId $newSubnetId -Zone "1","2","3"
$ip = $availableIPS[$availableIPS.count-1]
if ($oldlbFrontendConfigs.Zones.Equals($null)) {
    $lb | Set-AzLoadBalancerFrontendIpConfig -name $oldlbFrontendConfigs[0].Name -PrivateIpAddress $ip -SubnetId $newSubnetId
} 
else {
    $lb | Set-AzLoadBalancerFrontendIpConfig -name $oldlbFrontendConfigs[0].Name -PrivateIpAddress $ip -SubnetId $newSubnetId -Zone $oldlbFrontendConfigs.Zones
}
# Update Azure Load Balancer
$lb | Set-AzLoadBalancer

$lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $ILbName
$frontEndIpConfig = Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $lb -Name $NewFrontEndIPconfigName

#3. Inbound Nat Rules
$lbnatRules = $oldlbFrontendConfigs.InboundNatRules
foreach ($natRuleId in $lbNatRules) {
        $natRule = Get-AzLoadBalancerInboundNatRuleConfig -LoadBalancer $lb -Name ($natRuleId.Id).Split("/")[10]
        $floatingIPTest = $natRule.EnableFloatingIP
        $tcReset = $natRule.EnableTcpReset
        $natRuleName = $natRule.name
        if ($floatingIPTest.equals($true)) {
            if ($tcReset.Equals($True)) {
                $lb | Set-AzLoadBalancerInboundNatRuleConfig -Name $natRuleName  -FrontendIpConfiguration $frontEndIpConfig -Protocol $natRule.Protocol -FrontendPort $natRule.FrontendPort -BackendPort $natRule.BackendPort -EnableFloatingIP -EnableTcpReset
            } else {
                $lb | Set-AzLoadBalancerInboundNatRuleConfig -Name $natRuleName  -FrontendIpConfiguration $frontEndIpConfig -Protocol $natRule.Protocol -FrontendPort $natRule.FrontendPort -BackendPort $natRule.BackendPort -EnableFloatingIP
            }
        }
        else {
            if ($tcReset.Equals($True)) {
                $lb | Set-AzLoadBalancerInboundNatRuleConfig -Name $natRuleName  -FrontendIpConfiguration $frontEndIpConfig -Protocol $natRule.Protocol -FrontendPort $natRule.FrontendPort -BackendPort $natRule.BackendPort -EnableTcpReset 
            }
            else {
                $lb | Set-AzLoadBalancerInboundNatRuleConfig -Name $natRuleName  -FrontendIpConfiguration $frontEndIpConfig -Protocol $natRule.Protocol -FrontendPort $natRule.FrontendPort -BackendPort $natRule.BackendPort
            }
        }
}

#4. LoadBalancing Rules
$lbRuleConfigs = $oldlbFrontendConfigs.LoadBalancingRules
foreach ($ruleConfigId in $lbRuleConfigs) {
    $ruleConfig = Get-AzLoadBalancerRuleConfig -LoadBalancer $lb -Name ($ruleConfigId.Id).Split("/")[10]
    $floatingIPTest = $ruleConfig.EnableFloatingIP
    $loadDistribution = $ruleConfig.LoadDistribution
    $tcReset = $ruleConfig.EnableTcpReset
    $ruleConfigName = $ruleConfig.Name
    $backendPool = (Get-AzLoadBalancerBackendAddressPoolConfig -LoadBalancer $lb -Name ((($ruleConfig.BackendAddressPool.id).split("/"))[10]))
    if ($floatingIPTest.equals($true))
    {
        if ($tcReset.Equals($True)) {
            $lb | Set-AzLoadBalancerRuleConfig -Name $ruleConfigName -FrontendIPConfiguration $frontEndIpConfig -BackendAddressPool $backendPool -Probe (Get-AzLoadBalancerProbeConfig -LoadBalancer $lb -Name (($ruleConfig.Probe.id).split("/")[10])) -Protocol ($ruleConfig).protocol -FrontendPort ($ruleConfig).FrontendPort -BackendPort ($ruleConfig).BackendPort -IdleTimeoutInMinutes ($ruleConfig).IdleTimeoutInMinutes -EnableFloatingIP -LoadDistribution $loadDistribution -DisableOutboundSNAT -EnableTcpReset
        }
        else {
            $lb | Set-AzLoadBalancerRuleConfig -Name $ruleConfigName -FrontendIPConfiguration $frontEndIpConfig -BackendAddressPool $backendPool -Probe (Get-AzLoadBalancerProbeConfig -LoadBalancer $lb -Name (($ruleConfig.Probe.id).split("/")[10])) -Protocol ($ruleConfig).protocol -FrontendPort ($ruleConfig).FrontendPort -BackendPort ($ruleConfig).BackendPort -IdleTimeoutInMinutes ($ruleConfig).IdleTimeoutInMinutes -EnableFloatingIP -LoadDistribution $loadDistribution -DisableOutboundSNAT
        }
    }
    else
    {
        if ($tcReset.Equals($True)) {
            $lb | Set-AzLoadBalancerRuleConfig -Name $ruleConfigName -FrontendIPConfiguration $frontEndIpConfig -BackendAddressPool $backendPool -Probe (Get-AzLoadBalancerProbeConfig -LoadBalancer $lb -Name (($ruleConfig.Probe.id).split("/")[10])) -Protocol ($ruleConfig).protocol -FrontendPort ($ruleConfig).FrontendPort -BackendPort ($ruleConfig).BackendPort -IdleTimeoutInMinutes ($ruleConfig).IdleTimeoutInMinutes -LoadDistribution $loadDistribution -DisableOutboundSNAT -EnableTcpReset
        } 
        else {
            $lb | Set-AzLoadBalancerRuleConfig -Name $ruleConfigName -FrontendIPConfiguration $frontEndIpConfig -BackendAddressPool $backendPool -Probe (Get-AzLoadBalancerProbeConfig -LoadBalancer $lb -Name (($ruleConfig.Probe.id).split("/")[10])) -Protocol ($ruleConfig).protocol -FrontendPort ($ruleConfig).FrontendPort -BackendPort ($ruleConfig).BackendPort -IdleTimeoutInMinutes ($ruleConfig).IdleTimeoutInMinutes -LoadDistribution $loadDistribution -DisableOutboundSNAT
        }
    }

}

#5. Inbound Nat Pools
$lbnatPoolConfigs = $oldlbFrontendConfigs.InboundNatPools
foreach ($natPoolConfigId in $lbnatPoolConfigs) {
    $natPoolConfig = Get-AzLoadBalancerInboundNatPoolConfig -LoadBalancer $lb -Name ($natPoolConfigId.Id).Split("/")[10]
    $natPoolConfigName = $natPoolConfig.Name
    $lb | Set-AzLoadBalancerInboundNatPoolConfig -Name $natPoolConfigName -FrontendIpConfigurationId $frontEndIpConfig.Id -Protocol TCP -FrontendPortRangeStart $natPoolConfig.FrontendPortRangeStart  -FrontendPortRangeEnd $natPoolConfig.FrontendPortRangeEnd -BackendPort $natPoolConfig.BackendPort
}

#6 Update Azure Load Balancer
$lb | Set-AzLoadBalancer