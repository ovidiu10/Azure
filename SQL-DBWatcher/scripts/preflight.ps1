<#
.SYNOPSIS
    Preflight for the Database Watcher private-alerting PoC.

    1. Registers the resource providers Terraform needs.
    2. Discovers the EXISTING SQL MI, its VNet, and a usable private endpoint
       subnet, then writes a ready-to-use terraform.tfvars.

.DESCRIPTION
    Two failure modes this prevents:

    * Missing RP registration. azurerm only auto-registers a fixed set of
      providers; Microsoft.DatabaseWatcher and Microsoft.Dashboard are not in it.
      The resulting error appears mid-apply and is unhelpful, e.g.
        "API version '2024-10-01-preview' was not found for 'Microsoft.DatabaseWatcher'"

    * Wrong subnet in tfvars. The SQL MI subnet is delegated to
      Microsoft.Sql/managedInstances and CANNOT host a private endpoint. Picking
      it fails late, after the ADX cluster has already been created.

.EXAMPLE
    ./preflight.ps1
    ./preflight.ps1 -SqlMiName sqlmi-prod-01 -Location "East US"
    ./preflight.ps1 -WhatIf          # report only, register nothing, write nothing
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $SubscriptionId,
    [string] $SqlMiName,
    [string] $Location,
    [string] $OutFile = (Join-Path $PSScriptRoot "..\terraform\terraform.tfvars")
)

$ErrorActionPreference = 'Stop'

function Write-Step { param($m) Write-Host "`n=== $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    [ok]   $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "    [warn] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "    [FAIL] $m" -ForegroundColor Red }

# Database Watcher is not available in every region.
# https://learn.microsoft.com/azure/azure-sql/database-watcher-overview#regional-availability
$WatcherRegions = @(
    'canadacentral','canadaeast','centralus','eastus','eastus2','northcentralus','westus',
    'australiacentral','australiaeast','australiasoutheast','japanwest','koreacentral','southeastasia',
    'germanywestcentral','northeurope','westeurope','swedencentral','uksouth'
)

$RequiredProviders = @(
    'Microsoft.DatabaseWatcher',   # the watcher itself - almost never pre-registered
    'Microsoft.Dashboard',         # Azure Managed Grafana
    'Microsoft.Kusto',             # Azure Data Explorer
    'Microsoft.Network'            # private endpoints + private DNS
)

# ---------------------------------------------------------------- subscription
Write-Step "Subscription"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) not found in PATH."
}

if ($SubscriptionId) { az account set --subscription $SubscriptionId | Out-Null }

$acct = az account show -o json 2>$null | ConvertFrom-Json
if (-not $acct) { throw "Not signed in. Run: az login" }

Write-Ok "$($acct.name)  ($($acct.id))"
Write-Ok "tenant $($acct.tenantId)"
$SubscriptionId = $acct.id

# ---------------------------------------------------- resource providers
Write-Step "Resource providers"

$needRegister = @()
foreach ($rp in $RequiredProviders) {
    $state = az provider show --namespace $rp --query registrationState -o tsv 2>$null
    if ($state -eq 'Registered') {
        Write-Ok "$rp already registered"
    }
    else {
        Write-Warn "$rp is '$state'"
        $needRegister += $rp
    }
}

if ($needRegister.Count -gt 0) {
    if ($PSCmdlet.ShouldProcess(($needRegister -join ', '), 'Register resource providers')) {
        foreach ($rp in $needRegister) {
            Write-Host "    registering $rp ..." -NoNewline
            az provider register --namespace $rp --wait -o none
            $state = az provider show --namespace $rp --query registrationState -o tsv
            if ($state -eq 'Registered') { Write-Host " done" -ForegroundColor Green }
            else { Write-Host " still '$state'" -ForegroundColor Yellow }
        }
    }
    else {
        Write-Warn "skipped registration (WhatIf). Terraform will fail without these."
    }
}
else {
    Write-Ok "all required providers registered"
}

# ------------------------------------------------------------- find the SQL MI
Write-Step "SQL Managed Instance"

$mis = az sql mi list -o json | ConvertFrom-Json
if (-not $mis -or $mis.Count -eq 0) {
    throw "No SQL Managed Instance found in subscription $SubscriptionId."
}

if ($SqlMiName) {
    $mi = $mis | Where-Object { $_.name -eq $SqlMiName }
    if (-not $mi) { throw "SQL MI '$SqlMiName' not found. Available: $(($mis.name) -join ', ')" }
}
elseif ($mis.Count -eq 1) {
    $mi = $mis[0]
    Write-Ok "exactly one SQL MI found, using it"
}
else {
    Write-Warn "multiple SQL MIs found - re-run with -SqlMiName"
    $mis | ForEach-Object { Write-Host "           $($_.name)   rg=$($_.resourceGroup)   region=$($_.location)" }
    throw "Ambiguous SQL MI selection."
}

$miRg      = $mi.resourceGroup
$miSubnet  = $mi.subnetId
$miRegion  = $mi.location

Write-Ok "name   $($mi.name)"
Write-Ok "rg     $miRg"
Write-Ok "region $miRegion"
Write-Ok "fqdn   $($mi.fullyQualifiedDomainName)"

# --------------------------------------------------------------- VNet / subnet
Write-Step "Virtual network and private endpoint subnet"

# /subscriptions/../resourceGroups/RG/providers/Microsoft.Network/virtualNetworks/VNET/subnets/SUBNET
$parts       = $miSubnet -split '/'
$vnetRg      = $parts[4]
$vnetName    = $parts[8]
$miSubnetNm  = $parts[10]

Write-Ok "vnet   $vnetName (rg $vnetRg)"
Write-Ok "SQL MI subnet: $miSubnetNm  <- delegated, CANNOT host a private endpoint"

$subnets = az network vnet subnet list --vnet-name $vnetName --resource-group $vnetRg -o json | ConvertFrom-Json

$reserved = @('GatewaySubnet','AzureFirewallSubnet','AzureFirewallManagementSubnet','AzureBastionSubnet','RouteServerSubnet')

$candidates = $subnets | Where-Object {
    $_.name -ne $miSubnetNm -and
    $reserved -notcontains $_.name -and
    -not $_.delegations
}

if (-not $candidates -or $candidates.Count -eq 0) {
    Write-Err "No subnet in '$vnetName' can host a private endpoint."
    Write-Host ""
    Write-Host "    Every subnet is either delegated, reserved, or the SQL MI subnet."
    Write-Host "    Create one, for example:"
    Write-Host ""
    Write-Host "      az network vnet subnet create \"
    Write-Host "        --resource-group $vnetRg --vnet-name $vnetName \"
    Write-Host "        --name snet-private-endpoints --address-prefixes <free /27 or larger>"
    Write-Host ""
    Write-Host "    Existing address space in use:"
    $subnets | ForEach-Object { Write-Host "      $($_.name.PadRight(32)) $($_.addressPrefix)" }
    throw "No usable private endpoint subnet."
}

Write-Host ""
Write-Host "    Candidate subnets for the Grafana private endpoint:"
foreach ($s in $candidates) {
    $used = if ($s.ipConfigurations) { $s.ipConfigurations.Count } else { 0 }
    $pol  = if ($s.privateEndpointNetworkPolicies) { $s.privateEndpointNetworkPolicies } else { 'n/a' }
    Write-Host ("      {0}  prefix={1}  ips-in-use={2}  pe-policies={3}" -f $s.name.PadRight(30), $s.addressPrefix, $used, $pol)
}

$peSubnet = $candidates[0]
Write-Ok "selected: $($peSubnet.name)"
if ($candidates.Count -gt 1) {
    Write-Warn "first candidate chosen automatically - review before applying"
}

# ------------------------------------------------------------------- region
Write-Step "Region check"

$loc = if ($Location) { $Location } else { $miRegion }
$locKey = ($loc -replace '\s','').ToLower()

if ($WatcherRegions -contains $locKey) {
    Write-Ok "Database Watcher is available in '$loc'"
}
else {
    Write-Warn "Database Watcher is NOT available in '$loc'."
    Write-Warn "Pick a supported region in the same geography to limit bandwidth cost."
    Write-Warn "Supported: $($WatcherRegions -join ', ')"
}

# ------------------------------------------------------------------ tfvars
Write-Step "terraform.tfvars"

$tfvars = @"
# Generated by scripts/preflight.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm')
# Subscription: $($acct.name) ($SubscriptionId)
# REVIEW BEFORE APPLYING - especially private_endpoint_subnet_name.

# Existing SQL Managed Instance to monitor
sqlmi_name                = "$($mi.name)"
sqlmi_resource_group_name = "$miRg"

# Existing VNet / subnet for the inbound Grafana private endpoint.
# NOTE: '$miSubnetNm' is the SQL MI delegated subnet and must NOT be used here.
vnet_name                    = "$vnetName"
vnet_resource_group_name     = "$vnetRg"
private_endpoint_subnet_name = "$($peSubnet.name)"

# PoC resource group
resource_group_name = "rg-dbwatcher-grafana-poc"
location            = "$loc"
name_prefix         = "dbw"

# ADX sizing - Dev SKU is fine for a PoC, replace before production
adx_sku_name     = "Dev(No SLA)_Standard_E2a_v4"
adx_sku_capacity = 1

# Grafana
grafana_major_version = 13
grafana_sku_size      = "X1"

# Providers already registered by preflight.ps1
register_resource_providers = false

# PHASE SWITCH
#   false = phase 1, public access on, prove the pipeline works
#   true  = phase 2, public access OFF, the actual go/no-go gate
lock_down_public_access = false

create_grafana_private_dns_zone = true

tags = {
  workload = "dbwatcher-private-alerting-poc"
  owner    = "platform-data"
}
"@

$resolved = [System.IO.Path]::GetFullPath($OutFile)

if (Test-Path $resolved) {
    $backup = "$resolved.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Write-Warn "$resolved exists - backing up to $(Split-Path $backup -Leaf)"
    if ($PSCmdlet.ShouldProcess($resolved, 'Backup existing tfvars')) {
        Copy-Item $resolved $backup
    }
}

if ($PSCmdlet.ShouldProcess($resolved, 'Write terraform.tfvars')) {
    $dir = Split-Path $resolved -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tfvars | Set-Content -Path $resolved -Encoding utf8
    Write-Ok "wrote $resolved"
}
else {
    Write-Host ""
    Write-Host $tfvars
}

Write-Step "Next"
Write-Host @"
    1. Review terraform.tfvars - confirm private_endpoint_subnet_name is correct.
    2. cd terraform
       terraform init
       terraform plan -out main.tfplan
       terraform apply main.tfplan
    3. ./scripts/approve-private-endpoints.ps1
"@
