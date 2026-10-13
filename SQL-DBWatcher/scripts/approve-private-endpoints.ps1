<#
.SYNOPSIS
    Approves the three private endpoint connections this design creates.

.DESCRIPTION
    Terraform can request them but cannot approve them:
      - Database Watcher -> SQL MI           (shared private link)
      - Database Watcher -> ADX cluster      (shared private link)
      - Azure Managed Grafana -> ADX cluster (managed private endpoint)

    This mirrors production intent: the resource owner keeps the veto. In a customer
    environment the ADX/SQL owner runs this step, not the person deploying Grafana.

    Safe to re-run. Database Watcher creates its connections asynchronously, so one
    may still be Pending the first time through.

.PARAMETER TerraformDir
    Directory holding the terraform state. Defaults to ../terraform relative to
    this script, so the working directory does not matter.

.PARAMETER AdxId
    Resource id of the ADX cluster. Read from terraform output when omitted.

.PARAMETER SqlMiId
    Resource id of the SQL managed instance. Read from terraform output when omitted.

.EXAMPLE
    ./approve-private-endpoints.ps1

.EXAMPLE
    ./approve-private-endpoints.ps1 -AdxId "/subscriptions/..." -SqlMiId "/subscriptions/..."
#>
[CmdletBinding()]
param(
    [string] $TerraformDir = (Join-Path $PSScriptRoot '..\terraform'),
    [string] $AdxId,
    [string] $SqlMiId
)

$ErrorActionPreference = 'Stop'

# 'az network private-endpoint-connection' supports Microsoft.Sql/servers but NOT
# Microsoft.Sql/managedInstances, so managed instances go through the ARM API directly.
$MiApiVersion  = '2021-11-01'
$ApprovalNote  = 'Approved for Database Watcher private alerting PoC'

function Get-TfOutput {
    param([string] $Name)

    $tf = (Resolve-Path -LiteralPath $TerraformDir).Path
    # terraform exits 0 with empty stdout when run outside a state directory, so an
    # unset output is silent unless we check for it explicitly.
    $value = & terraform "-chdir=$tf" output -raw $Name 2>$null

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Could not read terraform output '$Name' from $tf. Has 'terraform apply' completed? Pass -AdxId/-SqlMiId to bypass terraform."
    }
    return $value.Trim()
}

function Approve-AdxPending {
    param([string] $ResourceId, [string] $Label)

    Write-Host ''
    Write-Host "=== $Label"

    $pending = az network private-endpoint-connection list --id $ResourceId -o json |
        ConvertFrom-Json |
        Where-Object { $_.properties.privateLinkServiceConnectionState.status -eq 'Pending' }

    if (-not $pending) { Write-Host '    no pending connections'; return }

    foreach ($c in $pending) {
        Write-Host "    approving: $($c.name)"
        az network private-endpoint-connection approve --id $c.id --description $ApprovalNote -o none
    }
}

function Approve-MiPending {
    param([string] $ResourceId, [string] $Label)

    Write-Host ''
    Write-Host "=== $Label"

    $url     = "https://management.azure.com$ResourceId/privateEndpointConnections?api-version=$MiApiVersion"
    $pending = (az rest --method get --url $url -o json | ConvertFrom-Json).value |
        Where-Object { $_.properties.privateLinkServiceConnectionState.status -eq 'Pending' }

    if (-not $pending) { Write-Host '    no pending connections'; return }

    $bodyFile = Join-Path ([IO.Path]::GetTempPath()) 'pec-approve.json'
    $body = @{ properties = @{ privateLinkServiceConnectionState = @{ status = 'Approved'; description = $ApprovalNote } } } |
        ConvertTo-Json -Depth 10 -Compress
    [IO.File]::WriteAllText($bodyFile, $body)

    try {
        foreach ($c in $pending) {
            Write-Host "    approving: $($c.name)"
            $putUrl = "https://management.azure.com$ResourceId/privateEndpointConnections/$($c.name)?api-version=$MiApiVersion"
            az rest --method put --url $putUrl --headers 'Content-Type=application/json' --body "@$bodyFile" -o none
        }
    }
    finally {
        Remove-Item -LiteralPath $bodyFile -ErrorAction SilentlyContinue
    }
}

if (-not $AdxId)   { $AdxId   = Get-TfOutput 'adx_cluster_id' }
if (-not $SqlMiId) { $SqlMiId = Get-TfOutput 'sqlmi_id' }

Approve-AdxPending -ResourceId $AdxId   -Label 'ADX cluster (Database Watcher + Grafana managed private endpoint)'
Approve-MiPending  -ResourceId $SqlMiId -Label 'SQL Managed Instance (Database Watcher)'

Write-Host ''
Write-Host '=== Current state'

Write-Host "--- $($AdxId.Split('/')[-1])"
az network private-endpoint-connection list --id $AdxId -o json | ConvertFrom-Json |
    Select-Object name, @{n = 'status'; e = { $_.properties.privateLinkServiceConnectionState.status } } |
    Format-Table -AutoSize | Out-String | Write-Host

Write-Host "--- $($SqlMiId.Split('/')[-1])"
(az rest --method get --url "https://management.azure.com$SqlMiId/privateEndpointConnections?api-version=$MiApiVersion" -o json | ConvertFrom-Json).value |
    Select-Object name, @{n = 'status'; e = { $_.properties.privateLinkServiceConnectionState.status } } |
    Format-Table -AutoSize | Out-String | Write-Host

Write-Host ''
Write-Host 'Done. Approval can take a few minutes to propagate.'
Write-Host "Re-run this script after any 'terraform apply' that adds a new private link."
