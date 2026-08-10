# Microsoft Azure Network Adapter (MANA) — existing VM SKUs

Azure is rolling out a new host generation (Intel Emerald Rapids + native NVMe + the **MANA** SmartNIC) to serve
capacity for **existing VM size families**. VM sizes, pricing, and networking limits do **not** change — only the
underlying physical host.

This folder collects the guidance, diagrams, and readiness scripts needed to answer the three questions customers
actually ask: *Am I affected? How do I check? What do I do if I'm not ready?*

---

## Contents

| File | What it covers |
|------|----------------|
| [`MANA-AccelNet-VF-Primer.md`](./MANA-AccelNet-VF-Primer.md) | **Start here if the concepts are new.** How Accelerated Networking, SR-IOV Virtual Functions, the synthetic/NetVSC interface, Mellanox, and MANA actually relate — the two-interface model, why the fallback path exists, what differs between Mellanox and MANA, and the four states a VM can be in. |
| [`MANA-Existing-VM-SKUs-Brief.md`](./MANA-Existing-VM-SKUs-Brief.md) | Main brief — what's changing, applicable VM series, readiness decision matrix, driver-vs-device verification, NVA `LegacyVMNVA` opt-out, tenant-wide Resource Graph query, and answers to commonly misunderstood points. |
| [`MANA-VM-Migration-Diagram.md`](./MANA-VM-Migration-Diagram.md) | Mermaid placement flow + lifecycle sequence — what triggers a move to MANA hardware and what happens at each branch. |
| [`MANA-checks-AzCLI.sh`](./MANA-checks-AzCLI.sh) | Azure CLI control-plane checks (VM size, AccelNet state, `LegacyVMNVA` tag + `reapply`) plus in-guest Linux/Windows verification commands. |
| [`MANA-checks-AzPowerShell.ps1`](./MANA-checks-AzPowerShell.ps1) | Same checks using the Az PowerShell module, including pushing in-guest commands via `Invoke-AzVMRunCommand`. |

---

## The 30-second version

**No action is required if Accelerated Networking is not enabled.** MANA does not affect the effective data path.

**If Accelerated Networking is enabled**, verify that the **MANA driver is present in the image**. There is no outage
either way — without the driver, networking falls back to the NetVSC synthetic adapter with performance comparable to
current-generation Mellanox hardware. But **NVA and high-concurrent-connection workloads can degrade**, so those need
verification before their region is enabled.

**Running VMs are not migrated in place.** Placement is only re-evaluated on VM create, redeploy, stop-deallocate +
start, or a platform maintenance event.

---

## The mistake to avoid

> "I'm running a supported OS, so I'm fine."

This is the single most common — and most expensive — misread. Three things are distinct:

| # | Layer | Passing this does **not** imply the next |
|---|-------|------------------------------------------|
| 1 | Accelerated Networking enabled | Enabling AccelNet says nothing about MANA readiness — a VM can run AccelNet today over the Mellanox path with no MANA driver. |
| 2 | OS **version** supports MANA | Upstream support ≠ the driver being in *your* image. Custom images, hardened golden images, and NVA appliance images routinely omit it. |
| 3 | MANA **driver present** in the running image | This is the one that matters. |

If the VF / synthetic-NIC model behind Accelerated Networking isn't already familiar, read
[**How Accelerated Networking, VFs, Mellanox, and MANA actually work**](./MANA-AccelNet-VF-Primer.md) first — most of
this confusion dissolves once the two-interface model is clear.

It's made worse by the fact that while a VM is still on Mellanox hardware, the in-guest **device** checks
(`lspci -d 1414:`, `Get-PnpDevice ... DEV_00BA`) return **empty whether or not the driver is installed** — so there is
no local signal that anything is wrong until placement changes and the workload is already degraded.

**Check the driver store, not the device:**

```bash
# Linux
grep -q mana /lib/modules/$(uname -r)/modules.builtin && echo "built into kernel"
find /lib/modules/$(uname -r)/kernel -name 'mana*.ko*' 2>/dev/null
```

```powershell
# Windows
pnputil /enum-drivers | Select-String -Context 0,5 'mana'
```

---

## If you need more time: the `LegacyVMNVA` tag

NVA and high-concurrency workloads can be temporarily held off MANA hardware with the **`LegacyVMNVA`** tag
(Azure Policy definition `e87a87f5-e6dd-4919-be21-abb0a4ea4630`). Two things are routinely gotten wrong:

1. **Two separate deadlines.** The tag protects a VM only if it is active **before that VM is placed** on MANA
   hardware — applying it afterward does not move an already-placed VM back. Separately, **31 May 2027** is when the
   tag stops being honored for everyone.
2. **Tagging alone does nothing.** Activate it with a **`reapply`** operation (`az vm reapply`, or the scale set
   reapply call), which re-evaluates placement **with no downtime**. Stop-deallocate + start is a last resort only.

Not available for VMs using a **custom OS image**. If your VMs run under an **on-demand capacity reservation (ODCR)**,
review the capacity and SLA implications with your Microsoft account team before applying the tag.

---

## Suggested order of use

1. Run the Resource Graph query in the brief to scope which VMs have AccelNet enabled — that's your affected population.
2. For those VMs, run the in-guest **driver** checks from the AzCLI / AzPowerShell scripts.
3. Driver present → done. Driver missing → remediate the image, or resize to **Intel v6 or later** (MANA-optimized by
   design, regardless of OS).
4. Need more time on an NVA or high-concurrency workload → apply `LegacyVMNVA`, then `reapply`.
5. Validate connectivity and network performance in non-production after any OS, driver, product, or tag change.

---

## Sources

- [Announcing MANA support for Existing VM SKUs](https://techcommunity.microsoft.com/blog/AzureInfrastructureBlog/announcing-microsoft-azure-network-adapter-mana-support-for-existing-vm-skus/4493279)
- [MANA support for existing VM sizes](https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-existing-sizes)
- [Windows VMs with MANA](https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-windows)
- [Linux VMs with MANA](https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-linux)
- [NVA opt-out (`LegacyVMNVA`)](https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-network-virtual-appliance-opt-out)
- [MANA overview](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-mana-overview)
- Windows MANA drivers: <https://aka.ms/manawindowsdrivers>

> **Scope and provenance.** This folder is compiled from publicly available Microsoft documentation and product
> announcements (linked above). It is a personal reference, not an official Microsoft communication.
>
> **Dates and regional timing are not authoritative here.** MANA enablement schedules are communicated
> per-subscription through **Azure Service Health**. Always check your own advisory for your regions and
> subscriptions.
