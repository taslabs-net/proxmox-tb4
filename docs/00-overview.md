# Overview

This guide walks you through building a high-performance Proxmox VE 9 cluster using Thunderbolt 4 for Ceph storage replication.

## Why Thunderbolt 4 for Ceph?

Traditional Ceph clusters require expensive 10GbE or 25GbE networking for the "cluster network" (the private network OSDs use to replicate data). Thunderbolt 4 offers:

| Feature | TB4 Advantage |
|---------|---------------|
| **Speed** | Up to 40 Gbps per port |
| **Latency** | Sub-millisecond (~0.6ms) |
| **Cost** | No switches needed - direct connection |
| **MTU** | Supports 65520 byte jumbo frames |
| **Simplicity** | Point-to-point, no network configuration |

## Architecture Concepts

### Three Networks, Three Purposes

```
┌─────────────────────────────────────────────────────────────────┐
│                      Your Home/Lab Network                       │
│                         (Router/Switch)                          │
└─────────────────────────────┬───────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
   ┌─────────┐           ┌─────────┐           ┌─────────┐
   │  Node 1 │           │  Node 2 │           │  Node 3 │
   │  (N2)   │           │  (N3)   │           │  (N4)   │
   └────┬────┘           └────┬────┘           └────┬────┘
        │                     │                     │
        │    TB4 Cables       │                     │
        │  ┌──────────────────┼─────────────────┐   │
        │  │                  │                 │   │
        └──┼──────────────────┼─────────────────┼───┘
           │                  │                 │
           ▼                  ▼                 ▼
      ┌─────────────────────────────────────────────┐
      │           TB4 Mesh (Ring Topology)           │
      │         Ceph Cluster Network Traffic         │
      └─────────────────────────────────────────────┘
```

### Network 1: Management Network (vmbr0)

**Purpose:** Proxmox cluster communication, SSH access, web UI

- Connects to your regular home/lab switch
- Typically 1GbE or 2.5GbE is sufficient
- Example: `10.11.11.0/24`

**What travels on this network:**
- Proxmox cluster heartbeats
- Web UI access (port 8006)
- SSH connections for administration
- VM migrations (can be slow, that's okay)

### Network 2: VM Network (vmbr1)

**Purpose:** Virtual machine traffic

- Your VMs' network connectivity
- Typically bridged to your LAN
- Example: `10.1.1.0/24` or same as your LAN

**What travels on this network:**
- VM traffic to/from the internet
- Inter-VM communication
- Backup traffic (optional)

### Network 3: TB4 Mesh Network (en05/en06)

**Purpose:** Ceph cluster traffic (OSD replication)

- Direct TB4 cable connections between nodes
- No switch needed!
- Example: `10.100.0.0/24`

**What travels on this network:**
- Ceph OSD replication (the heavy stuff)
- Ceph heartbeats
- Recovery/backfill traffic

## Mesh Topology Explained

### Why a Ring/Mesh?

With 3 nodes and 2 TB4 ports each, you create a **ring topology**:

```
         Node 1 (N2)
         en05   en06
          │       │
          │       │
     ┌────┘       └────┐
     │                 │
     ▼                 ▼
   Node 2 (N3)     Node 3 (N4)
   en05   en06     en05   en06
     │       │       │       │
     │       └───────┘       │
     │           ▲           │
     │      (direct link)    │
     └───────────────────────┘
```

Every node can reach every other node with **at most 1 hop**:
- N2 → N3: Direct via en05
- N2 → N4: Direct via en06
- N3 → N4: Direct via en06

### Point-to-Point Addressing

Each TB4 link gets its own /30 subnet (4 IPs, 2 usable):

| Link | Subnet | Node A IP | Node B IP |
|------|--------|-----------|-----------|
| N2-N3 (en05) | 10.100.0.0/30 | 10.100.0.1 | 10.100.0.2 |
| N2-N4 (en06) | 10.100.0.4/30 | 10.100.0.5 | 10.100.0.6 |
| N3-N4 (en06) | 10.100.0.8/30 | 10.100.0.9 | 10.100.0.10 |

## Why OpenFabric/SDN?

You have two choices for routing on the TB4 mesh:

### Option A: Static Routes (Simple)

- Configure static routes on each node
- Works fine, but manual to maintain
- No GUI integration

### Option B: OpenFabric via Proxmox SDN (Recommended)

- Dynamic routing protocol
- Automatic failover if a link goes down
- GUI integration in Proxmox
- Easier to troubleshoot

This guide covers **Option B** but notes where static routes differ.

## What You'll Build

By the end of this guide, you'll have:

1. **TB4 Mesh Network** - 3 nodes connected via TB4 with:
   - Consistent interface names (en05, en06)
   - 65520 MTU jumbo frames
   - Automatic interface bringup on boot/cable insertion

2. **OpenFabric Routing** - Dynamic routing with:
   - Sub-millisecond latency
   - Automatic failover
   - Proxmox GUI visibility

3. **Ceph Cluster** - High-performance storage with:
   - 3 monitors (quorum)
   - 6 OSDs (2 per node)
   - TB4 as cluster_network
   - Optimized for NVMe + high RAM

4. **Performance Tuning** - Optimizations for:
   - 64GB RAM nodes
   - 13th Gen Intel CPUs
   - NVMe storage
   - TB4 networking

## Time Estimate

| Phase | Time |
|-------|------|
| Prerequisites & Planning | 30 min |
| TB4 Foundation (modules, interfaces) | 1 hour |
| SDN Configuration | 30 min |
| Ceph Setup | 1 hour |
| Performance Tuning | 30 min |
| Testing & Validation | 30 min |
| **Total** | **~4 hours** |

## Next Steps

1. [Prerequisites](01-prerequisites.md) - Gather hardware and software requirements
2. [SSH Setup](02-ssh-setup.md) - Configure passwordless access
