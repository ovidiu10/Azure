# Managed Disk Assessor (ARG + Azure Monitor)

This app evaluates a pilot set of subscriptions for Azure Managed Disk optimization opportunities using:

- **Azure Resource Graph** for inventory and configuration context
- **Azure Monitor metrics** for utilization and saturation signals

## What it checks

- Disk utilization and potential over-/under-provisioning
- IOPS and throughput utilization, including near-limit behavior
- Sizing/SKU opportunities
- Performance and reliability risk signals
- Cost opportunities (unattached disks and right-size/SKU candidates)
- Scalable signals you can standardize across more subscriptions

## Prerequisites

1. Azure CLI installed
2. Logged in: `az login`
3. Resource Graph extension:
   - `az extension add --name resource-graph`
4. Reader access (or higher) across target subscriptions
5. Permission to read Azure Monitor metrics for disk resources

## Run

```powershell
cd "C:\WK\g\Azure\managed-disk-assessor"
python .\disk_assessor.py --subscriptions "<sub-1>,<sub-2>" --days 30 --workers 8 --output-dir .\out
```

Pilot mode (small subset):

```powershell
python .\disk_assessor.py --subscriptions "<sub-1>,<sub-2>" --days 30 --max-disks 50 --output-dir .\out
```

Console text report:

```powershell
python .\disk_assessor.py --subscriptions "<sub-1>,<sub-2>" --days 30 --text-report --top-findings 30 --output-dir .\out
```

## Output

- `out\managed_disk_findings.json` (full report: summary + findings + metric errors)
- `out\managed_disk_findings.csv` (flat findings for filtering and triage)

## Metrics used and why

The script uses these Azure Monitor platform metrics per managed disk:

- `Composite Disk Read Operations/Sec`
- `Composite Disk Write Operations/Sec`
- `Composite Disk Read Bytes/Sec`
- `Composite Disk Write Bytes/Sec`

Derived signals:

- **Total IOPS** = read ops/sec + write ops/sec
- **Total throughput (MB/s)** = (read bytes/sec + write bytes/sec) / 1024^2
- **P95 utilization** and **peak utilization** over hourly samples in the lookback window

Why these metrics:

- They directly map to the core managed disk capacity dimensions (IOPS and throughput).
- P95 captures sustained pressure better than one-off spikes.
- Peak helps detect burst/saturation windows that can still cause latency incidents.
- Comparing both against provisioned limits (or SKU-size baseline estimates) gives practical right-sizing and risk findings.

## Premium SSD v2 and Ultra SSD handling

- The assessor includes **PremiumV2_LRS** and **UltraSSD_LRS** in SKU cost and recommendation logic.
- For high-utilization Premium v2 / Ultra disks, recommendations prefer tuning provisioned IOPS/throughput first.
- For very low-utilization data disks, the report can suggest a lower SKU step:
  - `UltraSSD_LRS -> PremiumV2_LRS`
  - `PremiumV2_LRS -> Premium_LRS`
  - `Premium_LRS -> StandardSSD_LRS`

## Documentation links

- Azure Managed Disks overview: https://learn.microsoft.com/azure/virtual-machines/managed-disks-overview
- Managed Disk types and performance tiers: https://learn.microsoft.com/azure/virtual-machines/disks-types
- Managed Disk scalability/performance targets: https://learn.microsoft.com/azure/virtual-machines/disks-scalability-targets
- Azure Resource Graph overview: https://learn.microsoft.com/azure/governance/resource-graph/overview
- Azure Monitor metrics overview: https://learn.microsoft.com/azure/azure-monitor/essentials/data-platform-metrics

## Notes on recommendations

- Capacity limits are taken from provisioned disk properties when available.
- For SKUs where provisioned values are not returned, baseline limits are estimated from SKU/size tables.
- Cost impact is an approximation using SKU-level $/GB-month rates; validate against your regional pricing and reservations.
