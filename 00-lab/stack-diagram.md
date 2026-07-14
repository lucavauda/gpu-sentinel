# The GPU-node stack (what you're actually securing)

When a tenant "rents an H100," they touch the top box. The provider owns almost
everything below it. Your project lives in the **shaded middle** — the container
runtime, the OCI hooks, and the Linux plumbing — because that's where the
accessible attack surface and the real CVEs are.

```
┌─────────────────────────────────────────┐
│  Application  (PyTorch / your training) │   ← tenant
├─────────────────────────────────────────┤
│  CUDA runtime + libraries               │
├─────────────────────────────────────────┤
│  Container image (what the tenant ships)│  ▓ attacker-controlled
├═════════════════════════════════════════┤
│  Container runtime: containerd / CRI    │  ▓
│  OCI runtime: runc / crun               │  ▓  ← OCI LIFECYCLE HOOKS run HERE,
│  NVIDIA Container Toolkit / CDI hooks   │  ▓    on the HOST, with HOST privilege
├═════════════════════════════════════════┤     ← this boundary is the whole game
│  NVIDIA kernel driver + kernel modules  │
│  Linux kernel  (namespaces, cgroups,    │
│                 capabilities, IOMMU)    │
├─────────────────────────────────────────┤
│  Hypervisor / bare metal                │   ← provider
├─────────────────────────────────────────┤
│  GPU firmware                           │
├─────────────────────────────────────────┤
│  Physical GPU (PCIe, NVLink, MIG, DMA)  │
└─────────────────────────────────────────┘
```

Key idea you'll prove in Phase 2: the **container image is attacker-controlled**,
and an OCI hook that *executes on the host* while *trusting values from that image*
(like an inherited `LD_PRELOAD`) collapses the tenant↔host boundary. That single
sentence is NVIDIAScape.

The acronyms, placed on the diagram:
- **PCIe** — the bus between GPU and CPU/RAM (bottom box).
- **DMA / IOMMU** — a device reading/writing host RAM directly (DMA); the IOMMU
  is the kernel-level sandbox that confines it. "Can DMA attack host memory?" =
  "is the IOMMU confining this device?"
- **MIG** — partitioning one GPU into isolated instances (bottom box). Isolation
  question, needs A100/H100 to run — you'll study its threat model, not run it.
- **SR-IOV** — one PCIe device presenting many virtual functions to many VMs.
  Same "is the boundary real?" question as MIG.
