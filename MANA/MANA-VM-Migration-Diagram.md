# How a VM Moves from Old Hardware to New MANA Hardware

> Public sources only (Azure Infrastructure Blog + Microsoft Learn). Networking limits are tied to the **VM size,
> not the hardware** — the VM size stays the same; only the underlying host generation changes.

## 1. Placement flow — what triggers the move and what happens next

```mermaid
flowchart TD
    Start(["VM running on previous-gen host<br/>Mellanox ConnectX-3 / 4Lx / 5"])

    Start --> Trigger{"Placement / relocation<br/>trigger?"}
    Trigger -->|Stop-deallocate + start| Move
    Trigger -->|Standard Azure<br/>maintenance event| Move
    Trigger -->|New VM created in<br/>eligible series| Move
    Trigger -->|No trigger| Stay(["Stays on current host<br/>no change"])

    Move{"Is MANA-capable<br/>hardware available<br/>in the region?"}
    Move -->|No capacity yet| Stay
    Move -->|Yes| NVA{"VM with active<br/>LegacyVMNVA tag?<br/>(honored until 31 May 2027)"}

    NVA -->|Yes| Hold(["Held on non-MANA hardware<br/>until tag expiry / removal"])
    NVA -->|No| Land(["Lands on MANA-capable host<br/>Intel Emerald Rapids + NVMe + MANA NIC"])

    Land --> OS{"Guest OS supports<br/>the MANA driver?"}
    OS -->|Yes| Fast(["Accelerated data path<br/>higher throughput, lower latency,<br/>sub-second NIC firmware upgrades,<br/>Azure Boost accelerations"])
    OS -->|No| Fallback(["Falls back to NetVSC<br/>MANA VF visible but no MANA interface<br/>~ ConnectX-3/4Lx/5 performance<br/>degraded at high connection counts"])

    classDef good fill:#0b6a0b,color:#fff,stroke:#083d08;
    classDef warn fill:#8a6d00,color:#fff,stroke:#5c4900;
    classDef neutral fill:#274b6d,color:#fff,stroke:#16324a;
    class Fast good;
    class Fallback warn;
    class Stay,Hold neutral;
```

## 2. Lifecycle sequence — the move step by step

```mermaid
sequenceDiagram
    autonumber
    participant U as Customer
    participant CP as Azure Control Plane
    participant Old as Old host (Mellanox)
    participant New as MANA-capable host

    Note over Old: VM running, same VM size throughout
    U->>CP: Stop-deallocate + start<br/>(or Azure maintenance event)
    CP->>Old: Release VM from current host
    CP->>CP: Select capacity in region
    alt MANA capacity available & no LegacyVMNVA hold
        CP->>New: Place VM on MANA host<br/>(Emerald Rapids + NVMe + MANA NIC)
        New-->>CP: Single PCIe VF assigned (shared by all vNICs)
        alt Guest OS supports MANA
            New-->>U: Accelerated path active<br/>(MANA VF bonded to NetVSC)
        else OS lacks MANA driver
            New-->>U: NetVSC fallback<br/>(prev-gen performance)
        end
    else No capacity yet, or NVA opt-out active
        CP->>Old: Keep VM on previous-gen hardware
        Old-->>U: No change
    end
```

## Notes
- The VM **size/SKU does not change** — only the physical host generation. Networking limits follow the VM size.
- Multiple vNICs still receive **one shared PCIe Virtual Function** on MANA hardware.
- **No outage** either way: unsupported OSes keep connectivity via the NetVSC synthetic adapter.
- **NVAs or VMs** can pin to non-MANA hardware with the **`LegacyVMNVA`** tag until **31 May 2027**, after which it is no
  longer honored.
