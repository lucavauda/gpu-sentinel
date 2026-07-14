# Worksheet — DMA / IOMMU and the scary acronyms

Goal: turn PCIe / DMA / IOMMU / MIG / SR-IOV from intimidating words into "which
boundary is this, and is it real?" You'll *inspect* the ones you can and *model*
the ones you can't. Record answers inline (this file is yours to edit).

> Caveat: you're inside a Lima VM, so the IOMMU story is partial (nested virt).
> That's fine — the point is to learn what these knobs *are* and how you'd inspect
> them on real hardware. Where a command shows nothing, note *why*.

## 1. PCIe — the bus

List the PCI(e) devices the VM sees:
```bash
lspci        # install if missing: sudo apt-get install -y pciutils
```
- Q: which line (if any) would be the GPU on a real node? 
A GPU shows up in lspci as one of:

... VGA compatible controller: NVIDIA Corporation ...
... 3D controller: NVIDIA Corporation GH100 [H100] ...   ← data-center GPUs look like this
Data-center GPUs (H100/A100) usually appear as "3D controller" (no display output), consumer cards as "VGA compatible controller."
- Concept: PCIe is the highway between a device (GPU, NIC) and CPU/RAM. Every
  boundary below rides on it.

## 2. DMA + IOMMU — the memory boundary

DMA = a device reading/writing host RAM directly (fast, but dangerous if
unconfined). The **IOMMU** (Intel VT-d / AMD-Vi) is the kernel-level sandbox that
says which physical memory each device may touch.

```bash
dmesg | grep -i -e iommu -e dmar -e vt-d      # is an IOMMU active?
ls /sys/kernel/iommu_groups/ 2>/dev/null       # IOMMU groups (device isolation sets)
find /sys/kernel/iommu_groups/ -type l 2>/dev/null | head    # devices per group
```
- Q: is an IOMMU present/active here? If not, why not (think: nested VM)?
No. Empty iommu_groups, nothing in dmesg. The why is the interesting part: an IOMMU has to be exposed to the guest by the hypervisor (a "virtual IOMMU"/vIOMMU). Your Lima VM runs on Apple's virtualization stack, which doesn't hand the guest a vIOMMU by default — so the guest kernel simply has no IOMMU to configure. On bare-metal Linux you'd enable intel_iommu=on / amd_iommu=on, reboot, and /sys/kernel/iommu_groups/ would fill up. This is exactly why the worksheet said "inspect what you can, model the rest" — the IOMMU boundary is real hardware you can't fully exercise inside a nested VM.
- Q: in one sentence, "can DMA attack host memory?" really means: 
depends on the IOMMU: if it's present and in a translated/enforcing domain, device DMA is confined to assigned memory and the answer is no; if there's no IOMMU or it's in passthrough mode, the device can reach arbitrary host memory and the answer is yes.
  (hint: it's a question about whether the IOMMU is *confining* the device)
- Concept: an **IOMMU group** is the smallest unit that can be safely isolated /
  passed through. Devices sharing a group aren't isolated from each other.

## 3. VFIO — how a device gets confined/passed through

```bash
lsmod | grep -e vfio -e iommu 2>/dev/null
ls /dev/vfio 2>/dev/null
```
- Concept: `vfio-pci` binds a device so a VM can use it directly while the IOMMU
  restricts its DMA. This is the mechanism behind "secure passthrough."
- Q: why does passthrough *require* a working IOMMU to be safe? 
assthrough hands a physical device directly to a guest (VM or container). That device can issue DMA. Now the guest controls a piece of hardware that can write host physical memory directly:

Without an IOMMU: the guest programs the device to DMA into arbitrary host memory → it reads host secrets or overwrites host kernel structures → guest escapes to host through the device. The device becomes a DMA weapon.
With an IOMMU: the device's DMA is restricted to only the memory assigned to that guest. The device physically cannot reach host or other-tenant memory.
So the IOMMU is what makes passthrough safe — it's the boundary that confines a guest-controlled device to its lane.

## 4. MIG (Multi-Instance GPU) — model only

You almost certainly can't run MIG (needs A100/H100), so reason about it:
- MIG splits one physical GPU into up to 7 isolated instances (own compute,
  memory, cache slice) for different tenants.
- Q: state the MIG threat model in one line — what would "isolation broke" mean
  for tenant A and tenant B? tenant A can read, observe, or interfere with tenant B across the MIG partition — e.g. recover B's model weights left in GPU memory, infer B's activity via cache/timing side channels, or degrade B's compute.
- Q: which earlier boundary is MIG most analogous to — CPU cores, IOMMU groups,
  or SR-IOV VFs? Why? he best answer is SR-IOV VFs. Reason: both take one physical device and carve it into multiple hardware-isolated units handed to different tenants — MIG splits one GPU into instances; SR-IOV splits one device into virtual functions. Same "partition one device for many tenants" pattern (NVIDIA even combines them for vGPU). IOMMU groups are about which whole devices can be isolated from each other for DMA — related idea, but not "slice one device into many tenants." So: MIG ≈ SR-IOV.

## 5. SR-IOV — model only

- One physical PCIe device presents many **Virtual Functions (VFs)**, each handed
  to a different VM. Common on NICs, also used for GPU virtualization.
- Q: MIG and SR-IOV are asking the *same* security question. Write it once, in
  your own words: When one physical device is split among multiple tenants, is the isolation between the slices/VFs watertight — can one tenant read, observe, or affect another?

## The pattern (fill this in — it's the payoff)

DMA/IOMMU, MIG, and SR-IOV are all **isolation boundaries**. GPU multi-tenancy
security is fundamentally: GPU multi-tenancy security is fundamentally: do the isolation boundaries between tenants sharing physical GPU hardware actually hold when an adversary pushes on them?

Notice this is the *same shape* as the container↔host boundary you attacked in
Challenges A/B — just at a different layer of the stack. Put that observation in
your `NOTES.md`.
