# Managed Disk assessment with Azure CLI only (no Python)

## Feasibility evaluation

**Yes, this is possible with Azure CLI only** for inventory, utilization, near-limit detection, and basic right-size findings.

**Important limitation:** Azure CLI metrics aggregation supports `Average|Minimum|Maximum|Total|Count` but not percentile directly.  
So a strict CLI-only approach should use:

- `Maximum` for saturation/limit-risk signals
- `Average` for sustained-utilization signals

If you need exact P95/P99, export raw hourly points and compute percentile externally.

---

## 1) Prerequisites

```powershell
az login
az extension add --name resource-graph
```

---

## 2) Disk inventory (ARG)

```powershell
$subs = @(
  "<sub-1>",
  "<sub-2>"
)

$kql = @'
let vmDisks = (
    resources
    | where type =~ "microsoft.compute/virtualmachines"
    | project subscriptionId,
              vmId=id,
              vmName=name,
              vmSize=tostring(properties.hardwareProfile.vmSize),
              osDiskId=tostring(properties.storageProfile.osDisk.managedDisk.id),
              osCaching=tostring(properties.storageProfile.osDisk.caching),
              dataDisks=properties.storageProfile.dataDisks
    | project subscriptionId, vmId, vmName, vmSize, diskId=osDiskId, lun=-1, caching=osCaching, diskRole="OS"
    | union (
        resources
        | where type =~ "microsoft.compute/virtualmachines"
        | mv-expand dataDisk=properties.storageProfile.dataDisks
        | project subscriptionId,
                  vmId=id,
                  vmName=name,
                  vmSize=tostring(properties.hardwareProfile.vmSize),
                  diskId=tostring(dataDisk.managedDisk.id),
                  lun=toint(dataDisk.lun),
                  caching=tostring(dataDisk.caching),
                  diskRole="Data"
    )
);
resources
| where type =~ "microsoft.compute/disks"
| extend diskId=id
| project id, name, subscriptionId, resourceGroup, location,
          diskSku=tostring(sku.name),
          diskSizeGB=tolong(properties.diskSizeGB),
          diskState=tostring(properties.diskState),
          managedBy=tostring(managedBy),
          provisionedIops=tolong(properties.diskIOPSReadWrite),
          provisionedMBps=tolong(properties.diskMBpsReadWrite)
| join kind=leftouter vmDisks on subscriptionId, diskId
| project-away diskId1, subscriptionId1
'@

az graph query -q $kql --subscriptions $subs --first 1000 -o json > .\out\disks.json
```

---

## 3) Metrics pull (Azure Monitor) and CSV output

This creates a flat CSV with per-disk peak and average utilization signals.

```powershell
$start = (Get-Date).AddDays(-30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$end   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$disks = Get-Content .\out\disks.json | ConvertFrom-Json
$rows = @()

foreach ($d in $disks.data) {
  $m = az monitor metrics list `
    --resource $d.id `
    --metric "Composite Disk Read Operations/Sec" "Composite Disk Write Operations/Sec" "Composite Disk Read Bytes/Sec" "Composite Disk Write Bytes/Sec" `
    --aggregation Average Maximum `
    --interval PT1H `
    --start-time $start `
    --end-time $end `
    --only-show-errors -o json | ConvertFrom-Json

  $readIopsMax  = ($m.value | Where-Object {$_.name.value -eq "Composite Disk Read Operations/Sec"}).timeseries.data.maximum | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
  $writeIopsMax = ($m.value | Where-Object {$_.name.value -eq "Composite Disk Write Operations/Sec"}).timeseries.data.maximum | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
  $readBpsMax   = ($m.value | Where-Object {$_.name.value -eq "Composite Disk Read Bytes/Sec"}).timeseries.data.maximum | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
  $writeBpsMax  = ($m.value | Where-Object {$_.name.value -eq "Composite Disk Write Bytes/Sec"}).timeseries.data.maximum | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

  $readIopsAvg  = ($m.value | Where-Object {$_.name.value -eq "Composite Disk Read Operations/Sec"}).timeseries.data.average | Measure-Object -Average | Select-Object -ExpandProperty Average
  $writeIopsAvg = ($m.value | Where-Object {$_.name.value -eq "Composite Disk Write Operations/Sec"}).timeseries.data.average | Measure-Object -Average | Select-Object -ExpandProperty Average
  $readBpsAvg   = ($m.value | Where-Object {$_.name.value -eq "Composite Disk Read Bytes/Sec"}).timeseries.data.average | Measure-Object -Average | Select-Object -ExpandProperty Average
  $writeBpsAvg  = ($m.value | Where-Object {$_.name.value -eq "Composite Disk Write Bytes/Sec"}).timeseries.data.average | Measure-Object -Average | Select-Object -ExpandProperty Average

  $peakIops = [double]($readIopsMax + $writeIopsMax)
  $avgIops  = [double]($readIopsAvg + $writeIopsAvg)
  $peakMBps = [double](($readBpsMax + $writeBpsMax) / 1MB)
  $avgMBps  = [double](($readBpsAvg + $writeBpsAvg) / 1MB)

  $provIops = if ($d.provisionedIops) {[double]$d.provisionedIops} else {0}
  $provMBps = if ($d.provisionedMBps) {[double]$d.provisionedMBps} else {0}

  $peakIopsPct = if ($provIops -gt 0) { [math]::Round(($peakIops/$provIops)*100,2) } else { $null }
  $peakMBpsPct = if ($provMBps -gt 0) { [math]::Round(($peakMBps/$provMBps)*100,2) } else { $null }
  $avgIopsPct  = if ($provIops -gt 0) { [math]::Round(($avgIops/$provIops)*100,2) } else { $null }
  $avgMBpsPct  = if ($provMBps -gt 0) { [math]::Round(($avgMBps/$provMBps)*100,2) } else { $null }

  $finding = ""
  if (($peakIopsPct -ge 90) -or ($peakMBpsPct -ge 90)) {
    $finding = "Near limit - performance risk"
  } elseif (($avgIopsPct -le 20) -and ($avgMBpsPct -le 20) -and $d.managedBy) {
    $finding = "Low sustained utilization - right-size candidate"
  } elseif (-not $d.managedBy -or $d.diskState -eq "Unattached") {
    $finding = "Unattached disk - cost candidate"
  } else {
    $finding = "No immediate flag"
  }

  $rows += [pscustomobject]@{
    subscriptionId = $d.subscriptionId
    resourceGroup  = $d.resourceGroup
    diskName       = $d.name
    diskId         = $d.id
    diskSku        = $d.diskSku
    diskSizeGB     = $d.diskSizeGB
    vmName         = $d.vmName
    peakIops       = [math]::Round($peakIops,2)
    avgIops        = [math]::Round($avgIops,2)
    peakMBps       = [math]::Round($peakMBps,2)
    avgMBps        = [math]::Round($avgMBps,2)
    peakIopsPct    = $peakIopsPct
    peakMBpsPct    = $peakMBpsPct
    avgIopsPct     = $avgIopsPct
    avgMBpsPct     = $avgMBpsPct
    finding        = $finding
  }
}

$rows | Export-Csv .\out\managed_disk_cli_findings.csv -NoTypeInformation -Encoding UTF8
Write-Host "Created .\out\managed_disk_cli_findings.csv"
```

---

## 4) Notes for Premium SSD v2 and Ultra SSD

- Premium SSD v2 and Ultra SSD are configurable-performance disks.
- In CLI-only mode, prioritize these checks:
  1. `peakIopsPct` / `peakMBpsPct` near or above 90% => raise provisioned IOPS/throughput first.
  2. sustained low average utilization => evaluate lowering provisioned performance, or move to lower SKU only after SLO validation.

---

## 5) Recommended docs

- Managed disks overview: https://learn.microsoft.com/azure/virtual-machines/managed-disks-overview  
- Disk types (Premium v2 / Ultra / Premium / Standard): https://learn.microsoft.com/azure/virtual-machines/disks-types  
- Disk scalability and performance targets: https://learn.microsoft.com/azure/virtual-machines/disks-scalability-targets  
- Azure Resource Graph: https://learn.microsoft.com/azure/governance/resource-graph/overview  
- Azure Monitor metrics: https://learn.microsoft.com/azure/azure-monitor/essentials/data-platform-metrics  
