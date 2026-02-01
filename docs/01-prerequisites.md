# Prerequisites

Before starting, ensure you have all hardware and software requirements ready.

## Hardware Requirements

### Nodes (3x Minimum)

| Component | Requirement | Tested With |
|-----------|-------------|-------------|
| **TB4 Ports** | 2x per node | Intel 12th/13th Gen integrated |
| **RAM** | 32GB minimum, 64GB recommended | 64GB DDR5 |
| **CPU** | Modern Intel/AMD with good single-thread | Intel 13th Gen |
| **NVMe** | 1-2 drives per node for Ceph OSDs | 1TB NVMe |
| **Ethernet** | 1x for management network | 2.5GbE |

**Tested Hardware:**
- Minisforum MS-01 (excellent TB4 support)
- Intel NUC 12/13 Pro
- Other mini-PCs with dual TB4

### Thunderbolt 4 Cables

**Important:** Cable quality matters!

- Use certified **Thunderbolt 4** cables (not just USB-C)
- Length: 0.5m - 2m recommended (longer = more signal loss)
- Active cables for longer runs

**You need 3 cables** for a ring topology:
- N2 ↔ N3
- N3 ↔ N4  
- N4 ↔ N2

### Network Switch

You only need a basic switch for the **management network**:
- 1GbE or 2.5GbE is fine
- Managed switch optional (VLANs nice but not required)

**No switch needed for TB4!** That's the whole point.

## Software Requirements

### Proxmox VE 9.0+

This guide targets **Proxmox VE 9.x** which includes:
- Native OpenFabric SDN support
- Updated Ceph packages
- Better TB4 kernel support

**Check your version:**
```bash
pveversion
# Should show: pve-manager/9.x.x
```

### Repository Configuration

For the latest Ceph packages, enable the test repository:

```bash
# Check current repos
cat /etc/apt/sources.list.d/pve-enterprise.list
cat /etc/apt/sources.list.d/ceph.list

# You'll configure these during Ceph setup
```

## Network Planning

Before starting, plan your IP addressing:

### Management Network (Required)

Your existing network that connects to the outside world.

| Setting | Example | Your Value |
|---------|---------|------------|
| Network | 10.11.11.0/24 | __________ |
| Node 1 IP | 10.11.11.12 | __________ |
| Node 2 IP | 10.11.11.13 | __________ |
| Node 3 IP | 10.11.11.14 | __________ |
| Gateway | 10.11.11.1 | __________ |

### TB4 Mesh Network (Will Create)

A new, isolated network just for Ceph traffic.

| Setting | Example | Your Value |
|---------|---------|------------|
| Network | 10.100.0.0/24 | __________ |
| Node 1 Router ID | 10.100.0.12 | __________ |
| Node 2 Router ID | 10.100.0.13 | __________ |
| Node 3 Router ID | 10.100.0.14 | __________ |

### Point-to-Point Links

Each TB4 cable gets a /30 subnet:

| Link | Subnet | IP A | IP B |
|------|--------|------|------|
| N1-N2 en05 | 10.100.0.0/30 | .1 | .2 |
| N1-N3 en06 | 10.100.0.4/30 | .5 | .6 |
| N2-N3 en06 | 10.100.0.8/30 | .9 | .10 |

## Physical Setup

### Cable Your Nodes

Connect TB4 cables in a ring:

```
1. N2 port 1 (en05) → N3 port 1 (en05)
2. N3 port 2 (en06) → N4 port 1 (en05)
3. N4 port 2 (en06) → N2 port 2 (en06)
```

**Tips:**
- Label your cables!
- Ensure firm connections (TB4 can be finicky)
- Leave cables connected during entire setup

### Verify Physical Connectivity

On each node, check that TB4 controllers are detected:

```bash
# Should show Thunderbolt controllers
lspci | grep -i thunderbolt

# Example output:
# 00:0d.0 USB controller: Intel Corporation Device 7a60
# 00:0d.2 USB controller: Intel Corporation Device 7a62
# 00:0d.3 USB controller: Intel Corporation Device 7a63
```

## Checklist

Before proceeding, confirm:

- [ ] 3 nodes powered on and accessible via SSH
- [ ] Each node has 2 TB4 ports
- [ ] TB4 cables connected in ring topology
- [ ] Management network IPs assigned and reachable
- [ ] Proxmox VE 9.x installed on all nodes
- [ ] You have root SSH access to all nodes
- [ ] IP addressing planned (see tables above)
- [ ] `config.env` copied from `config.env.example` and edited

## Common Issues

### "I don't see Thunderbolt in lspci"

- Ensure TB4 is enabled in BIOS
- Some systems show as "USB controller" not "Thunderbolt"
- Check for "JHL7540" or similar Intel TB4 chip names

### "I only have 1 TB4 port per node"

You can still create a linear topology instead of a ring, but you lose redundancy. This guide assumes 2 ports.

### "My nodes are far apart"

TB4 passive cables work up to ~2m. For longer distances:
- Use active TB4 cables
- Consider fiber TB4 cables (expensive)
- Or accept slightly reduced reliability

## Next Steps

1. [SSH Setup](02-ssh-setup.md) - Configure passwordless access between nodes
