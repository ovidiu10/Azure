<#PSScriptInfo
.VERSION 0.1
.TAGS Azure, Az, LoadBalancer, AzNetworking
.changed by Ovi Timpanariu from original https://www.powershellgallery.com/packages/AzureILBUpgrade/5.0 
#>

<#
.DESCRIPTION
This script will help you update a Standard SKU Internal load balancer front end configuration load balancing rules, inbound NAT rules, inbound NAT pools.
.PARAMETER rgName
Name of ResourceGroup of the Standard Internal Load Balancer, like "microsoft_rg1"
.PARAMETER ILBName
Name of Standard Internal Load Balancer you want to update.
.PARAMETER OldFrontEndIPconfigName
Name of FrontendIP Standard Internal Load Balancer configs.
.PARAMETER NewFrontEndIPconfigName
Name of FrontendIP Standard Internal Load Balancer configs.
.EXAMPLE
./AzureILBMoveConfigs.ps1 -rgName "test_InternalUpgrade_rg" -ILbName "LBForUpgrade" -OldFrontEndIPconfigName "oldFE1" -NewFrontEndIPconfigName "newFE1"
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

#0. Backend subnet is always the same as the front end ip config - automatic association
$vnetName = ($lb.FrontendIpConfigurations.subnet.id).Split("/")[8]
$vnetRGName = ($lb.FrontendIpConfigurations.subnet.id).Split("/")[4]
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetRGName
$backendSubnetName = $lb.FrontendIpConfigurations.subnet.id.Split("/")[10]
$backendSubnet = Get-AzVirtualNetworkSubnetConfig -Name $backendSubnetName -VirtualNetwork $vnet
$ipRange = ($backendSubnet.AddressPrefix).split("/")[0]

$frontEndIpConfig = $lb.FrontendIpConfigurations
$newlbFrontendConfigs = $frontEndIpConfig | Where-Object {$_.Name -eq $NewFrontEndIPconfigName}
if ($newlbFrontendConfigs.Count -ne 1) {
    Write-Host "Frontend not exist"
    Exit 88
}
$oldlbFrontendConfigs = @()
$oldlbFrontendConfigs = $oldlbFrontendConfigs + ($frontEndIpConfig | Where-Object {$_.Name -eq $OldFrontEndIPconfigName})
if ($oldlbFrontendConfigs.Count -ne 1) {
    Write-Host "Frontend not exist"
    Exit 88
}
$frontEndIpConfig = Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $lb -Name $NewFrontEndIPconfigName

#1. Inbound Nat Rules
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

#2. LoadBalancing Rules
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

#3. Inbound Nat Pools
$lbnatPoolConfigs = $oldlbFrontendConfigs.InboundNatPools
foreach ($natPoolConfigId in $lbnatPoolConfigs) {
    $natPoolConfig = Get-AzLoadBalancerInboundNatPoolConfig -LoadBalancer $lb -Name ($natPoolConfigId.Id).Split("/")[10]
    $natPoolConfigName = $natPoolConfig.Name
    $lb | Set-AzLoadBalancerInboundNatPoolConfig -Name $natPoolConfigName -FrontendIpConfigurationId $frontEndIpConfig.Id -Protocol TCP -FrontendPortRangeStart $natPoolConfig.FrontendPortRangeStart  -FrontendPortRangeEnd $natPoolConfig.FrontendPortRangeEnd -BackendPort $natPoolConfig.BackendPort
}

#4 Update Azure Load Balancer
$lb | Set-AzLoadBalancer