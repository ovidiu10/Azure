#!/usr/bin/env python3
"""Managed Disk optimization assessor using Azure Resource Graph and Azure Monitor.

This tool:
1. Discovers managed disks and attachment metadata via ARG.
2. Pulls per-disk utilization metrics from Azure Monitor.
3. Produces actionable optimization findings and summary output.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import datetime as dt
import json
import math
import os
import subprocess
import sys
from dataclasses import dataclass
from typing import Any


ARG_QUERY = r"""
let vmDisks = (
    resources
    | where type =~ "microsoft.compute/virtualmachines"
    | project subscriptionId,
              vmId=id,
              vmName=name,
              vmSize=tostring(properties.hardwareProfile.vmSize),
              osDiskId=tostring(properties.storageProfile.osDisk.managedDisk.id),
              osCaching=tostring(properties.storageProfile.osDisk.caching),
              osWriteAccelerator=tobool(properties.storageProfile.osDisk.writeAcceleratorEnabled),
              dataDisks=properties.storageProfile.dataDisks
    | project subscriptionId, vmId, vmName, vmSize, diskId=osDiskId, lun=-1, caching=osCaching, writeAccelerator=osWriteAccelerator, diskRole="OS"
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
                  writeAccelerator=tobool(dataDisk.writeAcceleratorEnabled),
                  diskRole="Data"
    )
);
resources
| where type =~ "microsoft.compute/disks"
| extend diskId=id
| project
    diskId,
    id,
    name,
    subscriptionId,
    resourceGroup,
    location,
    diskSku=tostring(sku.name),
    diskSizeGB=tolong(properties.diskSizeGB),
    diskState=tostring(properties.diskState),
    managedBy=tostring(managedBy),
    burstEnabled=tobool(properties.burstingEnabled),
    maxShares=tolong(properties.maxShares),
    osType=tostring(properties.osType),
    tier=tostring(properties.tier),
    provisionedIops=tolong(properties.diskIOPSReadWrite),
    provisionedThroughputMBps=tolong(properties.diskMBpsReadWrite),
    tags
| join kind=leftouter vmDisks on subscriptionId, diskId
| project-away diskId1, subscriptionId1
"""


METRICS = (
    "Composite Disk Read Operations/Sec,Composite Disk Write Operations/Sec,"
    "Composite Disk Read Bytes/Sec,Composite Disk Write Bytes/Sec"
)


SIZE_STEPS_GB = [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32767]

# Approximation for baseline recommendations when provisioned values are not returned.
SKU_CAPACITY = {
    "Premium_LRS": [
        (4, 120, 25),
        (8, 240, 50),
        (16, 500, 100),
        (32, 1100, 125),
        (64, 2300, 200),
        (128, 5000, 250),
        (256, 7500, 250),
        (512, 7500, 250),
        (1024, 16000, 500),
        (2048, 18000, 750),
        (4096, 20000, 900),
        (8192, 20000, 900),
        (16384, 20000, 900),
        (32767, 20000, 900),
    ],
    "StandardSSD_LRS": [
        (4, 100, 25),
        (8, 200, 50),
        (16, 400, 60),
        (32, 500, 100),
        (64, 2000, 200),
        (128, 4000, 300),
        (256, 6000, 400),
        (512, 6000, 400),
        (1024, 6000, 500),
        (2048, 6000, 750),
        (4096, 6000, 750),
        (8192, 6000, 750),
        (16384, 6000, 750),
        (32767, 6000, 750),
    ],
    "Standard_LRS": [
        (32, 500, 60),
        (64, 500, 60),
        (128, 500, 60),
        (256, 500, 60),
        (512, 1300, 300),
        (1024, 2000, 500),
        (2048, 2000, 500),
        (4096, 2000, 500),
        (8192, 2000, 500),
        (16384, 2000, 500),
        (32767, 2000, 500),
    ],
}

APPROX_GB_MONTHLY_USD = {
    "Premium_LRS": 0.12,
    "PremiumV2_LRS": 0.10,
    "UltraSSD_LRS": 0.14,
    "StandardSSD_LRS": 0.06,
    "Standard_LRS": 0.045,
}

SKU_DOWNGRADE_TARGET = {
    "UltraSSD_LRS": "PremiumV2_LRS",
    "PremiumV2_LRS": "Premium_LRS",
    "Premium_LRS": "StandardSSD_LRS",
}


@dataclass
class DiskMetrics:
    samples: int
    peak_iops: float
    p95_iops: float
    peak_mbps: float
    p95_mbps: float


def run_az_json(args: list[str]) -> dict[str, Any]:
    cmd = ["az", *args, "-o", "json", "--only-show-errors"]
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    except FileNotFoundError:
        raise RuntimeError("Azure CLI not found. Install Azure CLI and run az login.")
    except subprocess.CalledProcessError as exc:
        details = (exc.stderr or exc.stdout or "").strip()
        raise RuntimeError(f"Azure CLI command failed: {' '.join(cmd)}\n{details}") from exc
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON from Azure CLI command: {' '.join(cmd)}") from exc


def query_disks(subscriptions: list[str], first: int = 1000) -> list[dict[str, Any]]:
    all_rows: list[dict[str, Any]] = []
    skip_token: str | None = None
    while True:
        args = ["graph", "query", "-q", ARG_QUERY, "--first", str(first), "--subscriptions", *subscriptions]
        if skip_token:
            args.extend(["--skip-token", skip_token])
        payload = run_az_json(args)
        chunk = payload.get("data", [])
        if not isinstance(chunk, list):
            raise RuntimeError("Unexpected ARG response shape: data is not a list.")
        all_rows.extend(chunk)
        skip_token = payload.get("skipToken")
        if not skip_token:
            break
    return all_rows


def get_disk_metrics(disk_id: str, start_time: str, end_time: str) -> DiskMetrics:
    payload = run_az_json(
        [
            "monitor",
            "metrics",
            "list",
            "--resource",
            disk_id,
            "--metric",
            METRICS,
            "--interval",
            "PT1H",
            "--aggregation",
            "Average",
            "Maximum",
            "--start-time",
            start_time,
            "--end-time",
            end_time,
        ]
    )
    series = _extract_metric_timeseries(payload)
    iops_hourly = []
    mbps_hourly = []
    for point in series.values():
        read_iops = point.get("Composite Disk Read Operations/Sec", 0.0)
        write_iops = point.get("Composite Disk Write Operations/Sec", 0.0)
        read_bps = point.get("Composite Disk Read Bytes/Sec", 0.0)
        write_bps = point.get("Composite Disk Write Bytes/Sec", 0.0)
        iops_hourly.append(read_iops + write_iops)
        mbps_hourly.append((read_bps + write_bps) / (1024.0 * 1024.0))

    if not iops_hourly:
        return DiskMetrics(samples=0, peak_iops=0.0, p95_iops=0.0, peak_mbps=0.0, p95_mbps=0.0)

    return DiskMetrics(
        samples=len(iops_hourly),
        peak_iops=max(iops_hourly),
        p95_iops=percentile(iops_hourly, 95),
        peak_mbps=max(mbps_hourly),
        p95_mbps=percentile(mbps_hourly, 95),
    )


def _extract_metric_timeseries(payload: dict[str, Any]) -> dict[str, dict[str, float]]:
    by_timestamp: dict[str, dict[str, float]] = {}
    for metric_obj in payload.get("value", []):
        name = metric_obj.get("name", {}).get("value", "")
        for ts_obj in metric_obj.get("timeseries", []):
            for data in ts_obj.get("data", []):
                ts = data.get("timeStamp")
                if not ts:
                    continue
                item = by_timestamp.setdefault(ts, {})
                value = data.get("maximum")
                if value is None:
                    value = data.get("average")
                if value is None:
                    value = 0.0
                item[name] = float(value)
    return by_timestamp


def percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    vals = sorted(values)
    rank = (p / 100.0) * (len(vals) - 1)
    lo = math.floor(rank)
    hi = math.ceil(rank)
    if lo == hi:
        return vals[lo]
    return vals[lo] + (vals[hi] - vals[lo]) * (rank - lo)


def estimated_capacity(disk: dict[str, Any]) -> tuple[int | None, int | None]:
    iops = to_int(disk.get("provisionedIops"))
    mbps = to_int(disk.get("provisionedThroughputMBps"))
    if iops and mbps:
        return iops, mbps
    sku = str(disk.get("diskSku") or "")
    size_gb = to_int(disk.get("diskSizeGB")) or 0
    table = SKU_CAPACITY.get(sku)
    if not table or size_gb <= 0:
        return None, None
    for max_size, est_iops, est_mbps in table:
        if size_gb <= max_size:
            return est_iops, est_mbps
    return table[-1][1], table[-1][2]


def downsize_one_step(size_gb: int) -> int | None:
    if size_gb not in SIZE_STEPS_GB:
        return None
    idx = SIZE_STEPS_GB.index(size_gb)
    if idx == 0:
        return None
    return SIZE_STEPS_GB[idx - 1]


def estimate_monthly_cost(disk: dict[str, Any], size_gb: int | None = None) -> float | None:
    sku = str(disk.get("diskSku") or "")
    gb = size_gb if size_gb is not None else to_int(disk.get("diskSizeGB"))
    if not gb:
        return None
    rate = APPROX_GB_MONTHLY_USD.get(sku)
    if rate is None:
        return None
    return round(gb * rate, 2)


def to_int(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return int(value)
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def classify_disk(disk: dict[str, Any], metrics: DiskMetrics) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    disk_id = disk.get("id")
    disk_name = disk.get("name")
    subscription_id = disk.get("subscriptionId")
    vm_name = disk.get("vmName")
    sku = str(disk.get("diskSku") or "")
    size_gb = to_int(disk.get("diskSizeGB")) or 0
    state = str(disk.get("diskState") or "")
    role = str(disk.get("diskRole") or "")
    write_acc = bool(disk.get("writeAccelerator"))

    est_iops, est_mbps = estimated_capacity(disk)
    iops_util = (metrics.p95_iops / est_iops * 100.0) if est_iops else None
    mbps_util = (metrics.p95_mbps / est_mbps * 100.0) if est_mbps else None

    base = {
        "diskId": disk_id,
        "diskName": disk_name,
        "subscriptionId": subscription_id,
        "resourceGroup": disk.get("resourceGroup"),
        "location": disk.get("location"),
        "vmName": vm_name,
        "vmSize": disk.get("vmSize"),
        "diskRole": role or "Unknown",
        "sku": sku,
        "sizeGB": size_gb,
        "state": state,
        "p95Iops": round(metrics.p95_iops, 2),
        "peakIops": round(metrics.peak_iops, 2),
        "p95ThroughputMBps": round(metrics.p95_mbps, 2),
        "peakThroughputMBps": round(metrics.peak_mbps, 2),
        "p95IopsUtilizationPct": round(iops_util, 2) if iops_util is not None else None,
        "p95ThroughputUtilizationPct": round(mbps_util, 2) if mbps_util is not None else None,
    }

    if state.lower() == "unattached" or not disk.get("managedBy"):
        monthly_cost = estimate_monthly_cost(disk)
        findings.append(
            {
                **base,
                "category": "Cost",
                "severity": "Medium",
                "finding": "Unattached managed disk",
                "recommendation": "Validate retention need; if not required, delete or snapshot-and-delete.",
                "estimatedMonthlySavingsUSD": monthly_cost,
            }
        )

    if metrics.samples == 0:
        findings.append(
            {
                **base,
                "category": "DataQuality",
                "severity": "Low",
                "finding": "No utilization metrics in selected window",
                "recommendation": "Confirm diagnostic data continuity and rerun with a longer window.",
            }
        )
        return findings

    if iops_util is not None and mbps_util is not None:
        high_util = max(iops_util, mbps_util)
        low_util = max(iops_util, mbps_util)

        if high_util >= 90 or metrics.peak_iops >= (est_iops or 10**9) * 0.95 or metrics.peak_mbps >= (est_mbps or 10**9) * 0.95:
            rec = "Scale up disk tier/size or redistribute IO load; validate app latency during peak windows."
            if sku in ("PremiumV2_LRS", "UltraSSD_LRS"):
                rec = (
                    "For configurable-performance disks, first increase provisioned IOPS/throughput if needed, "
                    "or move to higher tier if limits are still reached."
                )
            findings.append(
                {
                    **base,
                    "category": "PerformanceReliability",
                    "severity": "High",
                    "finding": "Disk operating close to provisioned limits",
                    "recommendation": rec,
                }
            )
        elif high_util >= 75:
            findings.append(
                {
                    **base,
                    "category": "Performance",
                    "severity": "Medium",
                    "finding": "Disk utilization consistently high",
                    "recommendation": "Track trend and plan proactive uplift before growth reaches sustained saturation.",
                }
            )

        if low_util <= 20:
            next_size = downsize_one_step(size_gb)
            current_cost = estimate_monthly_cost(disk, size_gb)
            downsize_cost = estimate_monthly_cost(disk, next_size) if next_size else None
            savings = None
            if current_cost is not None and downsize_cost is not None:
                savings = round(current_cost - downsize_cost, 2)
            rec = "Review right-sizing; sustained low utilization indicates potential over-provisioning."
            if next_size:
                rec += f" Candidate: downsize {size_gb}GB to {next_size}GB in same SKU."
            findings.append(
                {
                    **base,
                    "category": "CostSizing",
                    "severity": "Medium",
                    "finding": "Possible over-provisioned disk",
                    "recommendation": rec,
                    "estimatedMonthlySavingsUSD": savings,
                }
            )

            if sku in SKU_DOWNGRADE_TARGET and role.lower() == "data" and not write_acc and low_util <= 15:
                current = estimate_monthly_cost(disk, size_gb)
                target_sku = SKU_DOWNGRADE_TARGET[sku]
                target_rate = APPROX_GB_MONTHLY_USD.get(target_sku)
                savings_sku = round(current - (size_gb * target_rate), 2) if current is not None and target_rate else None
                findings.append(
                    {
                        **base,
                        "category": "CostSku",
                        "severity": "Low",
                        "finding": "Potential SKU downgrade opportunity",
                        "recommendation": (
                            f"Pilot {sku} -> {target_sku} for this low-utilization data disk "
                            "and validate latency/throughput SLOs."
                        ),
                        "estimatedMonthlySavingsUSD": savings_sku,
                        "targetSku": target_sku,
                    }
                )

    if bool(disk.get("burstEnabled")) and sku.startswith("Premium") and metrics.p95_iops > 0:
        findings.append(
            {
                **base,
                "category": "Configuration",
                "severity": "Low",
                "finding": "Burst capability enabled",
                "recommendation": "Confirm burst behavior is required and cost-effective for workload pattern.",
            }
        )

    return findings


def write_json(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, default=str)


def write_csv(path: str, findings: list[dict[str, Any]]) -> None:
    if not findings:
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write("")
        return
    fieldnames = sorted({k for row in findings for k in row.keys()})
    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in findings:
            writer.writerow(row)


def print_text_report(report: dict[str, Any], top_findings: int) -> None:
    summary = report.get("summary", {})
    findings = report.get("findings", [])
    errors = report.get("metricErrors", [])
    print("\n=== Managed Disk Assessment Report ===")
    print(f"Generated (UTC): {report.get('generatedAtUtc')}")
    print(f"Subscriptions: {', '.join(report.get('subscriptions', []))}")
    print(f"Window (days): {summary.get('assessmentWindowDays')}")
    print(f"Disks scanned: {summary.get('disksScanned')}")
    print(f"Total findings: {summary.get('totalFindings')}")
    print(f"Estimated monthly savings (approx): ${summary.get('estimatedMonthlySavingsUSD')}")

    by_sev = summary.get("findingsBySeverity", {})
    if by_sev:
        print("\nBy severity:")
        for sev, count in sorted(by_sev.items(), key=lambda x: x[0]):
            print(f"  - {sev}: {count}")

    by_cat = summary.get("findingsByCategory", {})
    if by_cat:
        print("\nBy category:")
        for cat, count in sorted(by_cat.items(), key=lambda x: x[0]):
            print(f"  - {cat}: {count}")

    if findings:
        severity_rank = {"High": 0, "Medium": 1, "Low": 2}
        ranked = sorted(
            findings,
            key=lambda f: (
                severity_rank.get(str(f.get("severity")), 99),
                str(f.get("category", "")),
                str(f.get("diskName", "")),
            ),
        )
        print(f"\nTop findings (showing {min(top_findings, len(ranked))} of {len(ranked)}):")
        for i, item in enumerate(ranked[:top_findings], 1):
            util_iops = item.get("p95IopsUtilizationPct")
            util_mbps = item.get("p95ThroughputUtilizationPct")
            util_text = []
            if util_iops is not None:
                util_text.append(f"IOPS P95 {util_iops}%")
            if util_mbps is not None:
                util_text.append(f"MBps P95 {util_mbps}%")
            util_joined = ", ".join(util_text) if util_text else "util n/a"
            print(
                f"{i:>2}. [{item.get('severity','?')}] {item.get('finding','')} | "
                f"disk={item.get('diskName','')} | vm={item.get('vmName','')} | "
                f"sku={item.get('sku','')} {item.get('sizeGB','')}GB | {util_joined}"
            )
            print(f"    -> {item.get('recommendation','')}")

    if errors:
        print(f"\nMetric collection errors: {len(errors)}")
        for err in errors[: min(10, len(errors))]:
            print(f"  - {err.get('diskId')}: {err.get('error')}")
        if len(errors) > 10:
            print(f"  ... and {len(errors) - 10} more (see JSON report)")


def build_summary(findings: list[dict[str, Any]], disks_scanned: int, days: int) -> dict[str, Any]:
    by_category: dict[str, int] = {}
    by_severity: dict[str, int] = {}
    total_savings = 0.0
    for item in findings:
        cat = item.get("category", "Unknown")
        sev = item.get("severity", "Unknown")
        by_category[cat] = by_category.get(cat, 0) + 1
        by_severity[sev] = by_severity.get(sev, 0) + 1
        savings = item.get("estimatedMonthlySavingsUSD")
        if isinstance(savings, (int, float)):
            total_savings += savings
    return {
        "assessmentWindowDays": days,
        "disksScanned": disks_scanned,
        "totalFindings": len(findings),
        "findingsByCategory": by_category,
        "findingsBySeverity": by_severity,
        "estimatedMonthlySavingsUSD": round(total_savings, 2),
        "scaleSignals": [
            "P95 utilization as % of provisioned IOPS and throughput",
            "Peak-to-provisioned ratio for saturation risk",
            "Disk attachment state and stale unattached age policy",
            "SKU/size right-size bands by workload class (OS/Data)",
            "Caching mode and write accelerator alignment with workload profile",
        ],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Managed Disk optimization assessor (ARG + Azure Monitor)")
    parser.add_argument("--subscriptions", required=True, help="Comma-separated subscription IDs")
    parser.add_argument("--days", type=int, default=30, help="Lookback window in days")
    parser.add_argument("--max-disks", type=int, default=0, help="Limit disks for pilot runs (0 = no limit)")
    parser.add_argument("--workers", type=int, default=8, help="Concurrent metric calls")
    parser.add_argument("--output-dir", default="out", help="Output directory for reports")
    parser.add_argument("--text-report", action="store_true", help="Print a detailed text report to console")
    parser.add_argument("--top-findings", type=int, default=25, help="Max findings to print in text report")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    subscriptions = [x.strip() for x in args.subscriptions.split(",") if x.strip()]
    if not subscriptions:
        print("No valid subscriptions provided.", file=sys.stderr)
        return 2

    end = dt.datetime.now(dt.timezone.utc)
    start = end - dt.timedelta(days=args.days)
    start_iso = start.isoformat(timespec="seconds").replace("+00:00", "Z")
    end_iso = end.isoformat(timespec="seconds").replace("+00:00", "Z")

    os.makedirs(args.output_dir, exist_ok=True)

    print("Querying disk inventory from Azure Resource Graph...")
    disks = query_disks(subscriptions=subscriptions)
    if args.max_disks > 0:
        disks = disks[: args.max_disks]
    print(f"Disks in scope: {len(disks)}")

    metric_results: dict[str, DiskMetrics] = {}
    metric_errors: list[dict[str, str]] = []
    print("Collecting Azure Monitor metrics...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        future_map = {
            pool.submit(get_disk_metrics, disk["id"], start_iso, end_iso): disk
            for disk in disks
            if disk.get("id")
        }
        for future in concurrent.futures.as_completed(future_map):
            disk = future_map[future]
            disk_id = disk["id"]
            try:
                metric_results[disk_id] = future.result()
            except Exception as exc:  # noqa: BLE001 - collect and continue
                metric_errors.append({"diskId": disk_id, "error": str(exc)})
                metric_results[disk_id] = DiskMetrics(0, 0.0, 0.0, 0.0, 0.0)

    findings: list[dict[str, Any]] = []
    for disk in disks:
        disk_id = disk.get("id")
        if not disk_id:
            continue
        findings.extend(classify_disk(disk, metric_results[disk_id]))

    summary = build_summary(findings, disks_scanned=len(disks), days=args.days)
    report = {
        "generatedAtUtc": end_iso,
        "subscriptions": subscriptions,
        "summary": summary,
        "findings": findings,
        "metricErrors": metric_errors,
    }

    json_path = os.path.join(args.output_dir, "managed_disk_findings.json")
    csv_path = os.path.join(args.output_dir, "managed_disk_findings.csv")
    write_json(json_path, report)
    write_csv(csv_path, findings)

    print(f"Report written: {json_path}")
    print(f"Flat findings CSV: {csv_path}")
    print(f"Findings: {summary['totalFindings']} | Estimated monthly savings (approx): ${summary['estimatedMonthlySavingsUSD']}")
    if metric_errors:
        print(f"Metric collection errors: {len(metric_errors)} (see metricErrors in JSON report)")
    if args.text_report:
        print_text_report(report, top_findings=max(1, args.top_findings))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
