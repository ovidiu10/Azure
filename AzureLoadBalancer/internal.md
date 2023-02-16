# Azure Load Balancer - Internal

This page is for help moving Azure Load Balancer Internal from Basic to Standard with Zone redundant frontend.
Current script always move the ALB "no-zone".

[Upgrade an internal basic load balancer - No outbound connections required](https://learn.microsoft.com/en-us/azure/load-balancer/upgrade-basicinternal-standard)

[Microsoft official migration script](https://www.powershellgallery.com/packages/AzureILBUpgrade/5.0)

Because all frontend IP configuration that are upgraded from ALB Basic SKU to ALB Standard SKU will be of type "no-zone" I build new script based for migrate with "zone redundant" frontend IP configuration.

## New scripts

<br />

Migrate from ALB internal Basic SKU to Standard SKU with zone redundant configuration [Migration script AzureILBUpgradetoZone.ps1](https://github.com/ovidiu10/Azure/blob/master/PowerShell/AzureILBStandardUpgradeToZone.ps1)

Migrate from ALB internal Standard SKU with frontend IP configuration "no-zone" to "zone redundant" [Migration script AzureILBStandardUpgradeToZone.ps1](https://github.com/ovidiu10/Azure/blob/master/PowerShell/AzureILBStandardUpgradeToZone.ps1)

### Microsoft documentation

<br />

[Load Balancer and Availability Zones](https://learn.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-availability-zones)