# Proxmox VE 9 + Thunderbolt 4 + Ceph Cluster Guide

[![Proxmox VE 9](https://img.shields.io/badge/Proxmox%20VE-9.x-E57000?style=flat&logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Ceph](https://img.shields.io/badge/Ceph-Reef-EF5C55?style=flat&logo=ceph&logoColor=white)](https://ceph.io/)
[![Thunderbolt 4](https://img.shields.io/badge/Thunderbolt-4-00A3E0?style=flat&logo=thunderbolt&logoColor=white)](https://www.intel.com/content/www/us/en/architecture-and-technology/thunderbolt/thunderbolt-technology-general.html)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![ShellCheck](https://github.com/taslabs-net/proxmox-tb4/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/taslabs-net/proxmox-tb4/actions/workflows/shellcheck.yml)
[![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat)](CONTRIBUTING.md)

A complete, beginner-friendly guide for building a high-performance Thunderbolt 4 mesh network with Ceph storage on Proxmox VE 9.

## What This Project Does

This guide helps you set up a **3-node Proxmox cluster** using **Thunderbolt 4** for ultra-fast Ceph storage replication. Instead of expensive 10GbE/25GbE network switches, you connect your nodes directly via TB4 cables in a mesh topology.

### Performance Results

| Metric | Result |
|--------|--------|
| Write Throughput | 1,300+ MB/s |
| Read Throughput | 1,760+ MB/s |
| Latency | Sub-millisecond (~0.6ms) |
| MTU | 65520 (jumbo frames) |
| Packet Loss | 0% |

## Prerequisites

### Hardware Requirements

- **3x nodes** with dual Thunderbolt 4 ports (tested on MS-01 mini-PCs)
- **64GB RAM** per node (recommended for Ceph performance)
- **NVMe drives** for Ceph OSDs
- **TB4 cables** for mesh connectivity (quality matters!)
- **Standard Ethernet** for management network

### Software Requirements

- Proxmox VE 9.0+ (with test repository for latest Ceph)
- Basic Linux/networking knowledge
- SSH access to all nodes

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/taslabs-net/proxmox-tb4.git
cd proxmox-tb4

# 2. Copy and edit the configuration
cp config.env.example config.env
nano config.env  # Edit with your node IPs and settings

# 3. Run the preflight check
./scripts/00-preflight-check.sh

# 4. Follow the guided setup
./scripts/01-setup-ssh.sh
./scripts/02-install-tb4-modules.sh
# ... continue with remaining scripts
```

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Network Architecture                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Management Network (vmbr0): 10.11.11.0/24                      │
│  ├── Proxmox cluster communication                              │
│  ├── SSH access                                                 │
│  └── Web UI access                                              │
│                                                                 │
│  VM Network (vmbr1): 10.1.1.0/24                                │
│  ├── Virtual machine traffic                                    │
│  └── Backup cluster communication                               │
│                                                                 │
│  TB4 Mesh Network (en05/en06): 10.100.0.0/24                    │
│  ├── Ceph cluster_network (OSD replication)                     │
│  ├── High-speed, low-latency                                    │
│  └── 65520 MTU jumbo frames                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Physical TB4 Mesh Topology (Ring):

        ┌──────────┐
        │    N2    │
        │ en05 en06│
        └──┬────┬──┘
           │    │
    en05   │    │   en06
           │    │
    ┌──────┘    └──────┐
    │                  │
    ▼                  ▼
┌──────────┐      ┌──────────┐
│    N3    │◄────►│    N4    │
│ en05 en06│      │ en05 en06│
└──────────┘      └──────────┘
     en06    ◄──►    en05
```

## Documentation

| Guide | Description |
|-------|-------------|
| [00 - Overview](docs/00-overview.md) | Architecture, concepts, and planning |
| [01 - Prerequisites](docs/01-prerequisites.md) | Hardware/software requirements |
| [02 - SSH Setup](docs/02-ssh-setup.md) | Passwordless SSH configuration |
| [03 - TB4 Foundation](docs/03-tb4-foundation.md) | Kernel modules and hardware detection |
| [04 - Network Config](docs/04-network-config.md) | Interface configuration and udev rules |
| [05 - SDN Setup](docs/05-sdn-setup.md) | Proxmox OpenFabric configuration |
| [06 - Ceph Setup](docs/06-ceph-setup.md) | Monitors, OSDs, and pools |
| [07 - Performance](docs/07-performance.md) | Optimization settings |
| [08 - Troubleshooting](docs/08-troubleshooting.md) | Common issues and fixes |
| [09 - Benchmarking](docs/09-benchmarking.md) | Testing and validation |

## Scripts

All scripts are designed to be:
- **Idempotent** - Safe to run multiple times
- **Interactive** - Confirm before making changes
- **Logged** - Track what was done for troubleshooting

```bash
scripts/
├── 00-preflight-check.sh      # Verify prerequisites
├── 01-setup-ssh.sh            # Deploy SSH keys
├── 02-install-tb4-modules.sh  # Load kernel modules
├── 03-configure-interfaces.sh # Set up TB4 networking
├── 04-setup-udev-rules.sh     # Create automation rules
├── 05-setup-systemd.sh        # Enable boot services
├── 06-verify-mesh.sh          # Test connectivity
├── lib/
│   ├── common.sh              # Shared functions
│   └── colors.sh              # Output formatting
└── utils/
    ├── troubleshoot.sh        # Diagnostic commands
    └── benchmark.sh           # Performance testing
```

## Configuration Templates

```bash
configs/
├── network/
│   └── interfaces.template    # /etc/network/interfaces template
├── systemd/
│   ├── 00-thunderbolt0.link   # Interface renaming
│   ├── 00-thunderbolt1.link
│   └── thunderbolt-interfaces.service
├── udev/
│   └── 10-tb-en.rules         # Hot-plug automation
└── scripts/
    ├── pve-en05.sh            # Interface bringup
    ├── pve-en06.sh
    └── thunderbolt-startup.sh # Boot-time init
```

## Acknowledgments

This project builds upon excellent foundational work:

- **[@scyto](https://gist.github.com/scyto)** - Original TB4 research and kernel module strategies
  - [Original TB4 Gist](https://gist.github.com/scyto/76e94832927a89d977ea989da157e9dc)
- **[@taslabs-net](https://gist.github.com/taslabs-net)** - PVE 9 integration and Ceph optimization
  - [Original PVE 9 Gist](https://gist.github.com/taslabs-net/9f6e06ab32833864678a4acbb6dc9131)

### Community Contributors

Thanks to everyone who helped refine this guide through testing and feedback:

- **@Allistah** - Ceph network bottleneck discovery, /32 addressing scheme
- **@aelhusseiniakl** - [GUI-focused alternative guide](https://gist.github.com/aelhusseiniakl/39e3fd9f29abda6153a3b5a0a5bc191b)
- **@Yearly1825** - Comprehensive boot fix script (udev + systemd ordering), cold boot module loading fix, PVE 9.1.4 testing
- **@ikiji-ns** - /31 addressing documentation
- **@pSyCr0**, **@scloder** - Testing and troubleshooting feedback

## FAQ

### Do I need expensive network switches?

No! The TB4 mesh connects nodes directly. You only need a basic switch for the management network.

### Can I use this with 2 nodes? Or 4+ nodes?

This guide is optimized for 3 nodes (the minimum for Ceph quorum). Adjustments are possible but not covered here.

### What about TB4 vs USB4?

USB4 should work similarly, but TB4 is recommended for consistent performance. Ensure your cables are certified.

### Is SDN/OpenFabric required?

No, you can use static point-to-point routes instead. SDN provides GUI integration and easier management.

## License

GPL-3.0 License - See [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Animated Visual
https://flarelylegal.com/docs/proxmox/tb4-ceph-cluster/

## Example Screenshot (MS-01)
<img width="768" height="768" alt="image" src="https://github.com/user-attachments/assets/92440dd0-7b82-46b2-88fe-5e8168699332" />


---

**Questions?** Open an issue or check the [Troubleshooting Guide](docs/08-troubleshooting.md).
