# Contributing

Thanks for your interest in contributing to the Proxmox TB4 + Ceph guide!

## Quick Start

```bash
# Clone the repo
git clone https://github.com/taslabs-net/proxmox-tb4.git
cd proxmox-tb4

# Copy and edit configuration
cp config.env.example config.env
nano config.env
```

## Ways to Contribute

### Documentation
- Fix typos or clarify explanations
- Add screenshots for GUI steps
- Document additional hardware configurations
- Improve troubleshooting guides

### Scripts
- Add new automation scripts
- Improve error handling
- Add support for different topologies
- Fix bugs in existing scripts

### Testing
- Test on different hardware and report results
- Verify scripts work on different Proxmox versions
- Benchmark and share performance numbers

## Code Standards

### Scripts
- Use `#!/bin/bash` shebang
- Use functions from `scripts/lib/common.sh` for consistency
- Include clear comments for complex logic
- Make scripts idempotent (safe to run multiple times)
- Test on Proxmox VE 9.x when possible

### Commits
- Follow [Conventional Commits](https://www.conventionalcommits.org/) format
- Examples:
  - `feat: add support for 4-node topology`
  - `fix: correct MTU setting in udev script`
  - `docs: clarify Ceph network configuration`

### Documentation
- Use clear, concise language
- Include command examples with expected output
- Target homelab users (beginner-friendly)
- Add diagrams where helpful

## Pull Requests

1. Fork the repo and create a feature branch
2. Make your changes
3. Test your changes if possible
4. Submit a PR with a clear description

## Hardware Contributions

If you've tested on different hardware, please share:
- Hardware model (mini-PC, server brand/model)
- TB4 controller details (`lspci | grep -i thunderbolt`)
- Any PCI path differences from the guide
- Performance benchmark results

## Questions?

Open an issue for discussion before starting major changes.
