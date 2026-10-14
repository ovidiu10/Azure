#Requires -Version 7.0
<#
.SYNOPSIS
Renders, deploys, verifies, or removes a public AKS DRANET sample workload.
.DESCRIPTION
Deploy creates a NEW Linux user pool on an EXISTING Azure CNI BYO-VNet cluster.
The existing namespace, cluster, VNet, and subnets are never created or deleted.
RemoveWorkload deletes only the configured pod and ResourceClaimTemplate.
Render is offline. Azure resource commands use the configured subscription explicitly.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [ValidateSet('Render', 'Deploy', 'Verify', 'RemoveWorkload')]
    [string]$Action = 'Render',

    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'generated'),

    [ValidateRange(30, 3600)]
    [int]$TimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-SampleTool {
    param([string]$Tool, [string[]]$Arguments)
    $output = & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Tool failed with exit code $LASTEXITCODE. Review the command error above."
    }
    return ($output -join "`n")
}

function Invoke-SampleAz {
    param([string[]]$Arguments)
    Invoke-SampleTool 'az' ($Arguments + @('--subscription', $config.subscriptionId, '--only-show-errors'))
}

function Invoke-SampleKubectl {
    param([string[]]$Arguments)
    Invoke-SampleTool 'kubectl' (@('--kubeconfig', $kubeconfigPath) + $Arguments)
}

function Get-SampleProperty {
    param($Object, [string]$Name)
    if ($Object.Contains($Name)) { return ,$Object[$Name] }
    return $null
}

function Test-SampleInterfaces {
    $interfaces = @(Invoke-SampleKubectl @(
        'exec', '--namespace', $config.namespace, $config.podName, '--',
        'ip', '-j', 'address', 'show'
    ) | ConvertFrom-Json -AsHashtable)
    $secondary = @($interfaces | Where-Object {
        $_.ifname -notin @('lo', 'eth0') -and
        @($_.addr_info | Where-Object { $_.scope -eq 'global' }).Count -gt 0
    })
    $primary = @($interfaces | Where-Object { $_.ifname -eq 'eth0' })
    if ($primary.Count -ne 1 -or $secondary.Count -lt 1) {
        throw 'Expected CNI eth0 plus an addressed secondary interface. Inspect the pod, ResourceClaim, and DRANET logs.'
    }
    $interfaces | ConvertTo-Json -Depth 20
    Invoke-SampleKubectl @('exec', '--namespace', $config.namespace, $config.podName, '--', 'ip', 'route', 'show')
    Invoke-SampleKubectl @('get', 'resourceclaims', '--namespace', $config.namespace, '-o', 'wide')
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
foreach ($name in @(
    'subscriptionId', 'resourceGroup', 'clusterName', 'nodePoolName', 'namespace',
    'podName', 'claimTemplateName', 'vmSize', 'image'
)) {
    $value = Get-SampleProperty $config $name
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value -match '[<>\r\n]') {
        throw "Configuration '$name' must be supplied, with no placeholder or line break."
    }
}
$subscriptionGuid = [guid]::Empty
if (-not [guid]::TryParse($config.subscriptionId, [ref]$subscriptionGuid)) {
    throw 'subscriptionId must be a subscription GUID.'
}
if ($config.nodePoolName -cnotmatch '^[a-z][a-z0-9]{0,11}$') {
    throw 'nodePoolName must start with a lowercase letter and contain 1-12 lowercase letters or digits.'
}
foreach ($name in @('namespace', 'podName', 'claimTemplateName')) {
    $maxLength = 63
    if ($config[$name].Length -gt $maxLength -or
        $config[$name] -cnotmatch '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$') {
        throw "'$name' must be a lowercase DNS label of at most $maxLength characters."
    }
}
if ($config.image -notmatch '(:[^/:\s]+|@sha256:[a-fA-F0-9]{64})$' -or $config.image -match ':latest$') {
    throw 'image must use an explicit non-latest tag or a sha256 digest.'
}
$subnets = Get-SampleProperty $config 'secondarySubnetIds'
if ($subnets -isnot [array] -or $subnets.Count -lt 1) {
    throw 'secondarySubnetIds must be a nonempty JSON array of subnet resource IDs.'
}
$subnetVnets = @(foreach ($subnet in $subnets) {
    if ($subnet -isnot [string] -or
        $subnet -notmatch '^(/subscriptions/([^/]+)/resourceGroups/[^/]+/providers/Microsoft\.Network/virtualNetworks/[^/]+)/subnets/[^/<>]+$') {
        throw 'Each secondarySubnetIds entry must be a complete Azure subnet resource ID.'
    }
    if ($Matches[2] -ne $config.subscriptionId) {
        throw 'All secondary subnets must be in the configured subscription.'
    }
    $Matches[1]
})
if (@($subnetVnets | Sort-Object -Unique).Count -ne 1) {
    throw 'All secondary NICs must use subnets in the same VNet.'
}
$nodeCount = Get-SampleProperty $config 'nodeCount'
if ($nodeCount -isnot [long] -and $nodeCount -isnot [int]) {
    throw 'nodeCount must be an integer.'
}
if ($nodeCount -lt 1 -or $nodeCount -gt 100) { throw 'nodeCount must be between 1 and 100.' }

$secondaryNics = @($subnets | ForEach-Object { @{ type = 'Standard'; vnetSubnetId = $_ } })
$sharedDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'shared'
$manifest = Get-Content -LiteralPath (Join-Path $sharedDirectory 'workload.template.json') -Raw |
    ConvertFrom-Json -AsHashtable
$claim = $manifest.items[0]
$pod = $manifest.items[1]
$claim.metadata.name = $config.claimTemplateName
$claim.metadata.namespace = $config.namespace
$pod.metadata.name = $config.podName
$pod.metadata.namespace = $config.namespace
$pod.spec.nodeSelector['kubernetes.azure.com/agentpool'] = $config.nodePoolName
$pod.spec.resourceClaims[0].resourceClaimTemplateName = $config.claimTemplateName
$pod.spec.containers[0].image = $config.image
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$nicPath = Join-Path $OutputDirectory 'secondary-nics.json'
$manifestPath = Join-Path $OutputDirectory 'workload.json'

if ($Action -eq 'Render') {
    if ($PSCmdlet.ShouldProcess($OutputDirectory, 'Write secondary NIC configuration and Kubernetes manifests')) {
        $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
        ConvertTo-Json -InputObject $secondaryNics -Depth 10 | Set-Content -LiteralPath $nicPath -Encoding utf8
        $manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $manifestPath -Encoding utf8
        Write-Output "Rendered: $nicPath"
        Write-Output "Rendered: $manifestPath"
    }
    return
}

foreach ($tool in @('az', 'kubectl')) { $null = Get-Command $tool -ErrorAction Stop }
if (-not $PSCmdlet.ShouldProcess(
    "$($config.subscriptionId)/$($config.resourceGroup)/$($config.clusterName), namespace $($config.namespace)",
    $Action
)) { return }

$cluster = Invoke-SampleAz @('aks', 'show', '-g', $config.resourceGroup, '-n', $config.clusterName, '-o', 'json') |
    ConvertFrom-Json -AsHashtable
$kubeconfigPath = Join-Path ([System.IO.Path]::GetTempPath()) ("aks-multinic-{0}.config" -f [guid]::NewGuid())
try {
    $null = Invoke-SampleAz @(
        'aks', 'get-credentials', '-g', $config.resourceGroup, '-n', $config.clusterName,
        '--file', $kubeconfigPath, '-o', 'none'
    )
    $null = Invoke-SampleKubectl @('get', 'namespace', $config.namespace, '-o', 'name')

    if ($Action -eq 'RemoveWorkload') {
        Invoke-SampleKubectl @('delete', 'pod', $config.podName, '--namespace', $config.namespace, '--ignore-not-found=true', '--wait=true', "--timeout=${TimeoutSeconds}s")
        Invoke-SampleKubectl @('delete', 'resourceclaimtemplate', $config.claimTemplateName, '--namespace', $config.namespace, '--ignore-not-found=true')
        Write-Output 'Workload removed. The namespace, node pool, and Azure resources remain; node costs continue.'
        return
    }
    if ($Action -eq 'Verify') {
        $null = Invoke-SampleKubectl @('wait', '--for=condition=Ready', "pod/$($config.podName)", '--namespace', $config.namespace, "--timeout=${TimeoutSeconds}s")
        Test-SampleInterfaces
        return
    }

    # Use the stricter public configuration guide requirement, not DRA's upstream GA version.
    if ([version]$cluster.kubernetesVersion -lt [version]'1.35.0') {
        throw 'The public AKS configuration guide requires Kubernetes 1.35 or later.'
    }
    if ($cluster.networkProfile.networkPlugin -ne 'azure') {
        throw 'This sample requires AKS-managed Azure CNI (optionally powered by Cilium).'
    }
    $extension = Invoke-SampleTool 'az' @('extension', 'show', '--name', 'aks-preview', '--only-show-errors', '-o', 'json') | ConvertFrom-Json
    if (-not $extension.version) { throw 'Install or update the aks-preview Azure CLI extension first.' }
    $helpText = Invoke-SampleTool 'az' @('aks', 'nodepool', 'add', '--help')
    if ($helpText -notmatch '--secondary-network-interfaces') {
        throw 'Update aks-preview: nodepool add does not expose --secondary-network-interfaces.'
    }
    $featureState = Invoke-SampleAz @(
        'feature', 'show', '--namespace', 'Microsoft.ContainerService', '--name', 'NetworkingMultiNICPreview',
        '--query', 'properties.state', '-o', 'tsv'
    )
    if ($featureState.Trim() -ne 'Registered') {
        throw 'Register NetworkingMultiNICPreview, wait for Registered, and refresh Microsoft.ContainerService first.'
    }
    $providerState = Invoke-SampleAz @(
        'provider', 'show', '--namespace', 'Microsoft.ContainerService',
        '--query', 'registrationState', '-o', 'tsv'
    )
    if ($providerState.Trim() -ne 'Registered') {
        throw 'Wait for Microsoft.ContainerService resource provider registration to complete first.'
    }
    $pools = @(Invoke-SampleAz @('aks', 'nodepool', 'list', '-g', $config.resourceGroup, '--cluster-name', $config.clusterName, '-o', 'json') |
        ConvertFrom-Json -AsHashtable)
    if (@($pools | Where-Object { $_.name -eq $config.nodePoolName }).Count -gt 0) {
        throw 'nodePoolName already exists. Deploy requires a new pool; use Verify for an existing deployment.'
    }
    $primarySubnetIds = @($pools | ForEach-Object { Get-SampleProperty $_ 'vnetSubnetId' } | Where-Object { $_ })
    if ($primarySubnetIds.Count -eq 0) {
        throw 'This sample requires an existing BYO-VNet AKS cluster with explicit node subnet IDs.'
    }
    $primaryVnet = $primarySubnetIds[0] -replace '/subnets/[^/]+$', ''
    if ($subnetVnets[0] -ne $primaryVnet) {
        throw 'The secondary subnets must belong to the same VNet as the existing primary NICs.'
    }
    foreach ($subnet in ($subnets | Sort-Object -Unique)) {
        $null = Invoke-SampleAz @('network', 'vnet', 'subnet', 'show', '--ids', $subnet, '-o', 'none')
    }
    $skus = @(Invoke-SampleAz @(
        'vm', 'list-skus', '--location', $cluster.location, '--resource-type', 'virtualMachines',
        '--size', $config.vmSize, '--all', '-o', 'json'
    ) | ConvertFrom-Json -AsHashtable)
    $sku = @($skus | Where-Object { $_.name -eq $config.vmSize })
    if ($sku.Count -ne 1) { throw 'The requested VM size was not found in the cluster region.' }
    $maxNics = @($sku[0].capabilities | Where-Object { $_.name -eq 'MaxNetworkInterfaces' })
    if ($maxNics.Count -ne 1 -or [int]$maxNics[0].value -lt (1 + $subnets.Count)) {
        throw 'The VM size must support one primary NIC plus every configured secondary NIC.'
    }
    if (@($sku[0].restrictions | Where-Object { $_.type -eq 'Location' }).Count -gt 0) {
        throw 'The VM size has a location restriction for this subscription.'
    }
    foreach ($resource in @(@('pod', $config.podName), @('resourceclaimtemplate', $config.claimTemplateName))) {
        $existing = Invoke-SampleKubectl @('get', $resource[0], $resource[1], '--namespace', $config.namespace, '--ignore-not-found=true', '-o', 'name')
        if ($existing) { throw "The configured $($resource[0]) already exists. Choose a new name to avoid overwriting a workload." }
    }

    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    ConvertTo-Json -InputObject $secondaryNics -Depth 10 | Set-Content -LiteralPath $nicPath -Encoding utf8
    $manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Invoke-SampleAz @(
        'aks', 'nodepool', 'add', '-g', $config.resourceGroup, '--cluster-name', $config.clusterName,
        '--name', $config.nodePoolName, '--mode', 'User', '--os-type', 'Linux',
        '--node-vm-size', $config.vmSize, '--node-count', [string]$nodeCount,
        '--vnet-subnet-id', $primarySubnetIds[0], '--secondary-network-interfaces', "@$nicPath", '-o', 'json'
    )
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $deviceClass = Invoke-SampleKubectl @('get', 'deviceclass', 'standard-secondary-nic', '--ignore-not-found=true', '-o', 'name')
        if ($deviceClass) { break }
        if ([datetime]::UtcNow -ge $deadline) {
            throw 'Timed out waiting for standard-secondary-nic. Inspect the managed DRANET DaemonSet. The new pool remains billable.'
        }
        Start-Sleep -Seconds 5
    } while ($true)
    Invoke-SampleKubectl @('get', 'daemonset', '-A')
    Invoke-SampleKubectl @('apply', '-f', $manifestPath)
    $null = Invoke-SampleKubectl @('wait', '--for=condition=Ready', "pod/$($config.podName)", '--namespace', $config.namespace, "--timeout=${TimeoutSeconds}s")
    Test-SampleInterfaces
}
finally {
    if (Test-Path -LiteralPath $kubeconfigPath) { Remove-Item -LiteralPath $kubeconfigPath -Force }
}
