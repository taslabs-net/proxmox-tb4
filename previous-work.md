SOURCE: https://gist.github.com/taslabs-net/9da77d302adb9fc3f10942d81f700a05

PVE9_TB4_Guide_Updated.md
PVE 9.1.1 TB4 + Ceph Guide
Updated as of: 2025-11-19 - Network architecture corrections applied

Network Architecture (UPDATED)
Cluster Management Network: 10.11.11.0/24 (vmbr0)

Primary cluster communication and SSH access
n2: 10.11.11.12
n3: 10.11.11.13
n4: 10.11.11.14
VM Network and Backup Cluster Network: 10.1.1.0/24 (vmbr1)

VM traffic and backup cluster communication
n2: 10.1.1.12
n3: 10.1.1.13
n4: 10.1.1.14
TB4 Mesh Network: 10.100.0.0/24 (en05/en06)

High-speed TB4 interfaces for Ceph cluster_network
Isolated from client I/O traffic
Provides optimal performance for Ceph OSD communication
SSH Key Setup (UPDATED)
Critical: Before proceeding with any configuration, you must set up SSH key authentication for passwordless access to all nodes.

Step 1: Generate SSH Key (if you don't have one)
# Generate a new SSH key (if needed):
ssh-keygen -t ed25519 -C "cluster-ssh-key" -f ~/.ssh/cluster_key
Step 2: Accept Host Keys (First Time Only)
IMPORTANT: Before running the deployment commands, you must SSH into each node once to accept the host key:

# Accept host keys for all nodes (type 'yes' when prompted):
ssh root@10.11.11.12 "echo 'Host key accepted for n2'"
ssh root@10.11.11.13 "echo 'Host key accepted for n3'"
ssh root@10.11.11.14 "echo 'Host key accepted for n4'"
Note: This step is required because the first SSH connection to each host requires accepting the host key. Without this, the automated deployment commands will fail.

Step 3: Deploy SSH Key to All Nodes
Deploy your public key to each node's authorized_keys:

# Deploy to n2 (10.11.11.12):
ssh root@10.11.11.12 "mkdir -p ~/.ssh && echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMGHoypdiKhldYlNUvW27uzutzewJ+X08Rlg/m7vmmtW cluster-ssh-key' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Deploy to n3 (10.11.11.13):
ssh root@10.11.11.13 "mkdir -p ~/.ssh && echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMGHoypdiKhldYlNUvW27uzutzewJ+X08Rlg/m7vmmtW cluster-ssh-key' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Deploy to n4 (10.11.11.14):
ssh root@10.11.11.14 "mkdir -p ~/.ssh && echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMGHoypdiKhldYlNUvW27uzutzewJ+X08Rlg/m7vmmtW cluster-ssh-key' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
Step 4: Test SSH Key Authentication
# Test passwordless SSH access to all nodes:
for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  echo "Testing SSH access to $node..."
  ssh root@$node "echo 'SSH key authentication working on $node'"
done
Expected result: All nodes should respond without prompting for a password.

TB4 Hardware Detection (UPDATED)
Step 1: Prepare All Nodes
Critical: Perform these steps on ALL mesh nodes (n2, n3, n4).

Load TB4 kernel modules:

# Execute on each node:
for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  ssh root@$node "echo 'thunderbolt' >> /etc/modules"
  ssh root@$node "echo 'thunderbolt-net' >> /etc/modules"
  ssh root@$node "modprobe thunderbolt && modprobe thunderbolt-net"
done
Verify modules loaded:

for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  echo "=== TB4 modules on $node ==="
  ssh root@$node "lsmod | grep thunderbolt"
done
Expected output: Both thunderbolt and thunderbolt_net modules present.

Step 2: Identify TB4 Hardware
Find TB4 controllers and interfaces:

for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  echo "=== TB4 hardware on $node ==="
  ssh root@$node "lspci | grep -i thunderbolt"
  ssh root@$node "ip link show | grep -E '(en0[5-9]|thunderbolt)'"
done
Expected: TB4 PCI controllers detected, TB4 network interfaces visible.

Step 3: Create Systemd Link Files
Critical: Create interface renaming rules based on PCI paths for consistent naming.

For all nodes (n2, n3, n4):

# Create systemd link files for TB4 interface renaming:
for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  ssh root@$node "cat > /etc/systemd/network/00-thunderbolt0.link << 'EOF'
[Match]
Path=pci-0000:00:0d.2
Driver=thunderbolt-net

[Link]
MACAddressPolicy=none
Name=en05
EOF"

  ssh root@$node "cat > /etc/systemd/network/00-thunderbolt1.link << 'EOF'
[Match]
Path=pci-0000:00:0d.3
Driver=thunderbolt-net

[Link]
MACAddressPolicy=none
Name=en06
EOF"
done
Note: Adjust PCI paths if different on your hardware (check with lspci | grep -i thunderbolt)

Verification: After creating the link files, reboot and verify:

for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  echo "=== Interface names on $node ==="
  ssh root@$node "ip link show | grep -E '(en05|en06)'"
done
Expected: Both en05 and en06 interfaces should be present and properly named.

TB4 Network Configuration (UPDATED)
Step 4: Configure Network Interfaces
CRITICAL: TB4 interfaces MUST be defined BEFORE the source /etc/network/interfaces.d/* line to prevent conflicts with SDN configuration.

Manual configuration required for each node:

Edit /etc/network/interfaces on each node and insert the following BEFORE the source /etc/network/interfaces.d/* line:

# Add at the TOP of the file, right after the header comments:
iface en05 inet manual #do not edit in GUI
iface en06 inet manual #do not edit in GUI
Then add the full interface definitions BEFORE the source line:

# n2 configuration:
auto en05
iface en05 inet static
    address 10.100.0.2/30
    mtu 65520

auto en06
iface en06 inet static
    address 10.100.0.5/30
    mtu 65520

# n3 configuration:
auto en05
iface en05 inet static
    address 10.100.0.6/30
    mtu 65520

auto en06
iface en06 inet static
    address 10.100.0.9/30
    mtu 65520

# n4 configuration:
auto en05
iface en05 inet static
    address 10.100.0.10/30
    mtu 65520

auto en06
iface en06 inet static
    address 10.100.0.14/30
    mtu 65520
IMPORTANT:

The auto keyword is CRITICAL - without it, interfaces won't come up automatically at boot
These static IP addresses are REQUIRED for Ceph's cluster_network
Without the IPs, OSDs will fail to start with "Cannot assign requested address" errors
Step 5: Enable systemd-networkd
Required for systemd link files to work:

# Enable and start systemd-networkd on all nodes:
for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  ssh root@$node "systemctl enable systemd-networkd && systemctl start systemd-networkd"
done
Step 6: Create Udev Rules and Scripts
Automation for reliable interface bringup on cable insertion:

Create udev rules:

for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  ssh root@$node "cat > /etc/udev/rules.d/10-tb-en.rules << 'EOF'
ACTION==\"move\", SUBSYSTEM==\"net\", KERNEL==\"en05\", RUN+=\"/usr/local/bin/pve-en05.sh\"
ACTION==\"move\", SUBSYSTEM==\"net\", KERNEL==\"en06\", RUN+=\"/usr/local/bin/pve-en06.sh\"
EOF"
done
Create interface bringup scripts:

# Create en05 bringup script for all nodes:
for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  ssh root@$node "cat > /usr/local/bin/pve-en05.sh << 'EOF'
#!/bin/bash
LOGFILE=\"/tmp/udev-debug.log\"
echo \"\$(date): en05 bringup triggered\" >> \"\$LOGFILE\"
for i in {1..5}; do
    {
        ip link set en05 up mtu 65520
        echo \"\$(date): en05 up successful on attempt \$i\" >> \"\$LOGFILE\"
        break
    } || {
        echo \"\$(date): Attempt \$i failed, retrying in 3 seconds...\" >> \"\$LOGFILE\"
        sleep 3
    }
done
EOF"
  ssh root@$node "chmod +x /usr/local/bin/pve-en05.sh"
done

# Create en06 bringup script for all nodes:
for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  ssh root@$node "cat > /usr/local/bin/pve-en06.sh << 'EOF'
#!/bin/bash
LOGFILE=\"/tmp/udev-debug.log\"
echo \"\$(date): en06 bringup triggered\" >> \"\$LOGFILE\"
for i in {1..5}; do
    {
        ip link set en06 up mtu 65520
        echo \"\$(date): en06 up successful on attempt \$i\" >> \"\$LOGFILE\"
        break
    } || {
        echo \"\$(date): Attempt \$i failed, retrying in 3 seconds...\" >> \"\$LOGFILE\"
        sleep 3
    }
done
EOF"
  ssh root@$node "chmod +x /usr/local/bin/pve-en06.sh"
done
Step 7: Verify Network Configuration
Test TB4 network connectivity:

# Test connectivity between nodes:
for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  echo "=== Testing TB4 connectivity from $node ==="
  ssh root@$node "ping -c 2 10.100.0.2 && ping -c 2 10.100.0.6 && ping -c 2 10.100.0.10"
done
Expected: All ping tests should succeed, confirming TB4 mesh connectivity.

Verify interface status:

for node in 10.11.11.12 10.11.11.13 10.11.11.14; do
  echo "=== TB4 interface status on $node ==="
  ssh root@$node "ip addr show en05 en06"
done
Expected: Both interfaces should show UP state with correct IP addresses.

Key Updates Made
SSH Access Network: Changed from 10.1.1.x to 10.11.11.x (cluster management network)
Network Architecture: Added clear explanation of the three network segments
All SSH Commands: Updated to use correct cluster management network
Verification Steps: Enhanced with better testing and troubleshooting
Network Summary
10.11.11.0/24 = Cluster Management Network (vmbr0) - SSH access and cluster communication
10.1.1.0/24 = VM Network and Backup Cluster Network (vmbr1) - VM traffic
10.100.0.0/24 = TB4 Mesh Network (en05/en06) - Ceph cluster_network for optimal performance
This updated version ensures all commands use the proper network architecture for your cluster setup.

For the complete guide with all phases, troubleshooting, and the best reading experience, visit: https://tb4.git.taslabs.net/

pve9tb4.md
Complete (ish) Thunderbolt 4 + Ceph Guide: Setup for Proxmox VE 9 BETA STABLE
Acknowledgments
This builds upon excellent foundational work by @scyto.

Original TB4 research from @scyto: https://gist.github.com/scyto/76e94832927a89d977ea989da157e9dc
My Original PVE 9 Writeup: https://gist.github.com/taslabs-net/9f6e06ab32833864678a4acbb6dc9131
Key contributions from @scyto's work:

TB4 hardware detection and kernel module strategies
Systemd networking and udev automation techniques
MTU optimization and performance tuning approaches
Overview:
This guide provides a step-by-step, tested (lightly) for building a high-performance Thunderbolt 4 + Ceph cluster on Proxmox VE 9 beta.

Lab Results:

TB4 Mesh Performance: Sub-millisecond latency, 65520 MTU, full mesh connectivity
Ceph Performance: 1,300+ MB/s write, 1,760+ MB/s read with optimizations
Reliability: 0% packet loss, automatic failover, persistent configuration
Integration: Full Proxmox GUI visibility and management
Hardware Environment:

Nodes: 3x systems with dual TB4 ports (tested on MS01 mini-PCs)
Memory: 64GB RAM per node (optimal for high-performance Ceph)
CPU: 13th Gen Intel (or equivalent high-performance processors)
Storage: NVMe drives for Ceph OSDs
Network: TB4 mesh (10.100.0.0/24) + management (10.11.12.0/24)
Software Stack:

Proxmox VE: 9.0 beta with native SDN OpenFabric support
Ceph: Nautilus with BlueStore, LZ4 compression, 2:1 replication
OpenFabric: IPv4-only mesh routing for simplicity and performance
Prerequisites: What You Need
Physical Requirements
3 nodes minimum: Each with dual TB4 ports (tested with MS01 mini-PCs)
TB4 cables: Quality TB4 cables for mesh connectivity
Ring topology: Physical connections n2→n3→n4→n2 (or similar mesh pattern)
Management network: Standard Ethernet for initial setup and management
Software Requirements
Proxmox VE 9.0 beta (test repository)
SSH root access to all nodes
Basic Linux networking knowledge
Patience: TB4 mesh setup requires careful attention to detail!
Network Planning
Management network: 10.11.12.0/24 (adjust to your environment)
TB4 cluster network: 10.100.0.0/24 (for Ceph cluster traffic)
Router IDs: 10.100.0.12 (n2), 10.100.0.13 (n3), 10.100.0.14 (n4)
Phase 1: Thunderbolt Foundation Setup
Step 1: Prepare All Nodes
Critical: Perform these steps on ALL mesh nodes (n2, n3, n4).

Load TB4 kernel modules:

# Execute on each node:
for node in n2 n3 n4; do
  ssh $node "echo 'thunderbolt' >> /etc/modules"
  ssh $node "echo 'thunderbolt-net' >> /etc/modules"  
  ssh $node "modprobe thunderbolt && modprobe thunderbolt-net"
done
Verify modules loaded:

for node in n2 n3 n4; do
  echo "=== TB4 modules on $node ==="
  ssh $node "lsmod | grep thunderbolt"
done
Expected output: Both thunderbolt and thunderbolt_net modules present.

Step 2: Identify TB4 Hardware
Find TB4 controllers and interfaces:

for node in n2 n3 n4; do
  echo "=== TB4 hardware on $node ==="
  ssh $node "lspci | grep -i thunderbolt"
  ssh $node "ip link show | grep -E '(en0[5-9]|thunderbolt)'"
done
Expected: TB4 PCI controllers detected, TB4 network interfaces visible.

Step 3: Create Systemd Link Files
Critical: Create interface renaming rules based on PCI paths for consistent naming.

For all nodes (n2, n3, n4):

# Create systemd link files for TB4 interface renaming:
for node in n2 n3 n4; do
  ssh $node "cat > /etc/systemd/network/00-thunderbolt0.link << 'EOF'
[Match]
Path=pci-0000:00:0d.2
Driver=thunderbolt-net

[Link]
MACAddressPolicy=none
Name=en05
EOF"

  ssh $node "cat > /etc/systemd/network/00-thunderbolt1.link << 'EOF'
[Match]
Path=pci-0000:00:0d.3
Driver=thunderbolt-net

[Link]
MACAddressPolicy=none
Name=en06
EOF"
done
Note: Adjust PCI paths if different on your hardware (check with lspci | grep -i thunderbolt)

Step 4: Configure Network Interfaces
Add TB4 interfaces to network configuration with optimal settings:

# Configure TB4 interfaces on all nodes:
for node in n2 n3 n4; do
  ssh $node "cat >> /etc/network/interfaces << 'EOF'

auto en05
iface en05 inet manual
    mtu 65520

auto en06
iface en06 inet manual
    mtu 65520
EOF"
done
Step 5: Enable systemd-networkd
Required for systemd link files to work:

# Enable and start systemd-networkd on all nodes:
for node in n2 n3 n4; do
  ssh $node "systemctl enable systemd-networkd && systemctl start systemd-networkd"
done
Step 6: Create Udev Rules and Scripts
Automation for reliable interface bringup on cable insertion:

Create udev rules:

for node in n2 n3 n4; do
  ssh $node "cat > /etc/udev/rules.d/10-tb-en.rules << 'EOF'
ACTION==\"add|move\", SUBSYSTEM==\"net\", KERNEL==\"en05\", RUN+=\"/usr/local/bin/pve-en05.sh\"
ACTION==\"add|move\", SUBSYSTEM==\"net\", KERNEL==\"en06\", RUN+=\"/usr/local/bin/pve-en06.sh\"
EOF"
done
Create interface bringup scripts:

# Create en05 bringup script for all nodes:
for node in n2 n3 n4; do
  ssh $node "cat > /usr/local/bin/pve-en05.sh << 'EOF'
#!/bin/bash
LOGFILE=\"/tmp/udev-debug.log\"
echo \"\$(date): en05 bringup triggered\" >> \"\$LOGFILE\"
for i in {1..5}; do
    {
        ip link set en05 up mtu 65520
        echo \"\$(date): en05 up successful on attempt \$i\" >> \"\$LOGFILE\"
        break
    } || {
        echo \"\$(date): Attempt \$i failed, retrying in 3 seconds...\" >> \"\$LOGFILE\"
        sleep 3
    }
done
EOF"
  ssh $node "chmod +x /usr/local/bin/pve-en05.sh"
done

# Create en06 bringup script for all nodes:
for node in n2 n3 n4; do
  ssh $node "cat > /usr/local/bin/pve-en06.sh << 'EOF'
#!/bin/bash
LOGFILE=\"/tmp/udev-debug.log\"
echo \"\$(date): en06 bringup triggered\" >> \"\$LOGFILE\"
for i in {1..5}; do
    {
        ip link set en06 up mtu 65520
        echo \"\$(date): en06 up successful on attempt \$i\" >> \"\$LOGFILE\"
        break
    } || {
        echo \"\$(date): Attempt \$i failed, retrying in 3 seconds...\" >> \"\$LOGFILE\"
        sleep 3
    }
done
EOF"
  ssh $node "chmod +x /usr/local/bin/pve-en06.sh"
done
Step 7: Update Initramfs and Reboot
Apply all TB4 configuration changes:

# Update initramfs on all nodes:
for node in n2 n3 n4; do
  ssh $node "update-initramfs -u -k all"
done

# Reboot all nodes to apply changes:
echo "Rebooting all nodes - wait for them to come back online..."
for node in n2 n3 n4; do
  ssh $node "reboot"
done

# Wait and verify after reboot:
echo "Waiting 60 seconds for nodes to reboot..."
sleep 60

# Verify TB4 interfaces after reboot:
for node in n2 n3 n4; do
  echo "=== TB4 interfaces on $node after reboot ==="
  ssh $node "ip link show | grep -E '(en05|en06)'"
done
Expected result: TB4 interfaces should be named en05 and en06 with proper MTU settings.

Step 8: Enable IPv4 Forwarding
Essential: TB4 mesh requires IPv4 forwarding for OpenFabric routing.

# Configure IPv4 forwarding on all nodes:
for node in n2 n3 n4; do
  ssh $node "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf"
  ssh $node "sysctl -p"
done
Verify forwarding enabled:

for node in n2 n3 n4; do
  echo "=== IPv4 forwarding on $node ==="
  ssh $node "sysctl net.ipv4.ip_forward"
done
Expected: net.ipv4.ip_forward = 1 on all nodes.

Step 9: Create Systemd Service for Boot Reliability
Ensure TB4 interfaces come up automatically on boot:

Create systemd service:

for node in n2 n3 n4; do
  ssh $node "cat > /etc/systemd/system/thunderbolt-interfaces.service << 'EOF'
[Unit]
Description=Configure Thunderbolt Network Interfaces
After=network.target thunderbolt.service
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/thunderbolt-startup.sh

[Install]
WantedBy=multi-user.target
EOF"
done
Create startup script:

for node in n2 n3 n4; do
  ssh $node "cat > /usr/local/bin/thunderbolt-startup.sh << 'EOF'
#!/bin/bash
# Thunderbolt interface startup script
LOGFILE=\"/var/log/thunderbolt-startup.log\"

echo \"\$(date): Starting Thunderbolt interface configuration\" >> \"\$LOGFILE\"

# Wait up to 30 seconds for interfaces to appear
for i in {1..30}; do
    if ip link show en05 &>/dev/null && ip link show en06 &>/dev/null; then
        echo \"\$(date): Thunderbolt interfaces found\" >> \"\$LOGFILE\"
        break
    fi
    echo \"\$(date): Waiting for Thunderbolt interfaces... (\$i/30)\" >> \"\$LOGFILE\"
    sleep 1
done

# Configure interfaces if they exist
if ip link show en05 &>/dev/null; then
    /usr/local/bin/pve-en05.sh
    echo \"\$(date): en05 configured\" >> \"\$LOGFILE\"
fi

if ip link show en06 &>/dev/null; then
    /usr/local/bin/pve-en06.sh
    echo \"\$(date): en06 configured\" >> \"\$LOGFILE\"
fi

echo \"\$(date): Thunderbolt configuration completed\" >> \"\$LOGFILE\"
EOF"
  ssh $node "chmod +x /usr/local/bin/thunderbolt-startup.sh"
done
Enable the service:

for node in n2 n3 n4; do
  ssh $node "systemctl daemon-reload"
  ssh $node "systemctl enable thunderbolt-interfaces.service"
done
Note: This service ensures TB4 interfaces come up even if udev rules fail to trigger on boot.

Phase 2: Proxmox SDN Configuration
Step 4: Create OpenFabric Fabric in GUI
Location: Datacenter → SDN → Fabrics

Click: "Add Fabric" → "OpenFabric"

Configure in the dialog:

Name: tb4
IPv4 Prefix: 10.100.0.0/24
IPv6 Prefix: (leave empty for IPv4-only)
Hello Interval: 3 (default)
CSNP Interval: 10 (default)
Click: "OK"

Expected result: You should see a fabric named tb4 with Protocol OpenFabric and IPv4 10.100.0.0/24

image
Step 5: Add Nodes to Fabric
Still in: Datacenter → SDN → Fabrics → (select tb4 fabric)

Click: "Add Node"

Configure for n2:

Node: n2
IPv4: 10.100.0.12
IPv6: (leave empty)
Interfaces: Select en05 and en06 from the interface list
Click: "OK"

Repeat for n3: IPv4: 10.100.0.13, interfaces: en05, en06

Repeat for n4: IPv4: 10.100.0.14, interfaces: en05, en06

Expected result: You should see all 3 nodes listed under the fabric with their IPv4 addresses and interfaces (en05, en06 for each)

Important: You need to manually configure /30 point-to-point addresses on the en05 and en06 interfaces to create mesh connectivity. Example addressing scheme:

n2: en05: 10.100.0.1/30, en06: 10.100.0.5/30
n3: en05: 10.100.0.9/30, en06: 10.100.0.13/30
n4: en05: 10.100.0.17/30, en06: 10.100.0.21/30
These /30 subnets allow each interface to connect to exactly one other interface in the mesh topology. Configure these addresses in the Proxmox network interface settings for each node.

image
Step 6: Apply SDN Configuration
Critical: This activates the mesh - nothing works until you apply!

In GUI: Datacenter → SDN → "Apply" (button in top toolbar)

Expected result: Status table shows all nodes with "OK" status like this:

SDN     Node    Status
localnet... n3   OK
localnet... n1   OK  
localnet... n4   OK
localnet... n2   OK
image
Step 7: Start FRR Service
Critical: OpenFabric routing requires FRR (Free Range Routing) to be running.

# Start and enable FRR on all mesh nodes:
for node in n2 n3 n4; do
  ssh $node "systemctl start frr && systemctl enable frr"
done
Verify FRR is running:

for node in n2 n3 n4; do
  echo "=== FRR status on $node ==="
  ssh $node "systemctl status frr | grep Active"
done
Expected output:

=== FRR status on n2 ===
     Active: active (running) since Mon 2025-01-27 20:15:23 EST; 2h ago
=== FRR status on n3 ===
     Active: active (running) since Mon 2025-01-27 20:15:25 EST; 2h ago
=== FRR status on n4 ===
     Active: active (running) since Mon 2025-01-27 20:15:27 EST; 2h ago
Command-line verification:

# Check SDN services on all nodes:
for node in n2 n3 n4; do
  echo "=== SDN status on $node ==="
  ssh $node "systemctl status frr | grep Active"
done
Expected output:

=== SDN status on n2 ===
     Active: active (running) since Mon 2025-01-27 20:15:23 EST; 2h ago
=== SDN status on n3 ===
     Active: active (running) since Mon 2025-01-27 20:15:25 EST; 2h ago
=== SDN status on n4 ===
     Active: active (running) since Mon 2025-01-27 20:15:27 EST; 2h ago
Phase 3: Mesh Verification and Testing
Step 8: Verify Interface Configuration
Check TB4 interfaces are up with correct settings:

for node in n2 n3 n4; do
  echo "=== TB4 interfaces on $node ==="
  ssh $node "ip addr show | grep -E '(en05|en06|10\.100\.0\.)'"
done
Expected output example (n2):

=== TB4 interfaces on n2 ===
    inet 10.100.0.12/32 scope global dummy_tb4
11: en05: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65520 qdisc fq_codel state UP group default qlen 1000
    inet 10.100.0.1/30 scope global en05
12: en06: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65520 qdisc fq_codel state UP group default qlen 1000
    inet 10.100.0.5/30 scope global en06
What this shows:

Router ID address: 10.100.0.12/32 on dummy_tb4 interface
TB4 interfaces UP: en05 and en06 with state UP
Jumbo frames: mtu 65520 on both interfaces
Point-to-point addresses: /30 subnets for mesh connectivity
Step 9: Test OpenFabric Mesh Connectivity
Critical test: Verify full mesh communication works.

# Test router ID connectivity (should be sub-millisecond):
for target in 10.100.0.12 10.100.0.13 10.100.0.14; do
  echo "=== Testing connectivity to $target ==="
  ping -c 3 $target
done
Expected output:

=== Testing connectivity to 10.100.0.12 ===
PING 10.100.0.12 (10.100.0.12) 56(84) bytes of data.
64 bytes from 10.100.0.12: icmp_seq=1 ttl=64 time=0.618 ms
64 bytes from 10.100.0.12: icmp_seq=2 ttl=64 time=0.582 ms
64 bytes from 10.100.0.12: icmp_seq=3 ttl=64 time=0.595 ms
--- 10.100.0.12 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms

=== Testing connectivity to 10.100.0.13 ===
PING 10.100.0.13 (10.100.0.13) 56(84) bytes of data.
64 bytes from 10.100.0.13: icmp_seq=1 ttl=64 time=0.634 ms
64 bytes from 10.100.0.13: icmp_seq=2 ttl=64 time=0.611 ms
64 bytes from 10.100.0.13: icmp_seq=3 ttl=64 time=0.598 ms
--- 10.100.0.13 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2004ms
What to look for:

All pings succeed: 3 received, 0% packet loss
Sub-millisecond latency: time=0.6xx ms (typical ~0.6ms)
No timeouts or errors: Should see response for every packet
If connectivity fails: TB4 interfaces may need manual bring-up after reboot:

# Bring up TB4 interfaces manually:
for node in n2 n3 n4; do
  ssh $node "ip link set en05 up mtu 65520"
  ssh $node "ip link set en06 up mtu 65520"
  ssh $node "ifreload -a"
done
Step 10: Verify Mesh Performance
Test mesh latency and basic throughput:

# Test latency between router IDs:
for node in n2 n3 n4; do
  echo "=== Latency test from $node ==="
  ssh $node "ping -c 5 -i 0.2 10.100.0.12 | tail -1"
  ssh $node "ping -c 5 -i 0.2 10.100.0.13 | tail -1"
  ssh $node "ping -c 5 -i 0.2 10.100.0.14 | tail -1"
done
Expected: Round-trip times under 1ms consistently.

Phase 4: High-Performance Ceph Integration
Step 11: Install Ceph on All Mesh Nodes
Install Ceph packages on all mesh nodes:

# Initialize Ceph on mesh nodes:
for node in n2 n3 n4; do
  echo "=== Installing Ceph on $node ==="
  ssh $node "pveceph install --repository test"
done
Step 12: Create Ceph Directory Structure
Essential: Proper directory structure and ownership:

# Create base Ceph directories with correct ownership:
for node in n2 n3 n4; do
  ssh $node "mkdir -p /var/lib/ceph && chown ceph:ceph /var/lib/ceph"
  ssh $node "mkdir -p /etc/ceph && chown ceph:ceph /etc/ceph"
done
Step 13: Create First Monitor and Manager
CLI Approach:

# Create initial monitor on n2:
ssh n2 "pveceph mon create"
Expected output:

Monitor daemon started successfully on node n2.
Created new cluster with fsid: 12345678-1234-5678-9abc-123456789abc
GUI Approach:

Location: n2 node → Ceph → Monitor → "Create"
Result: Should show green "Monitor created successfully" message
Verify monitor creation:

ssh n2 "ceph -s"
Expected output:

  cluster:
    id:     12345678-1234-5678-9abc-123456789abc
    health: HEALTH_OK
 
  services:
    mon: 1 daemons, quorum n2 (age 2m)
    mgr: n2(active, since 1m)
    osd: 0 osds: 0 up, 0 in
 
  data:
    pools:   0 pools, 0 pgs
    objects: 0 objects, 0 B
    usage:   0 B used, 0 B / 0 B avail
    pgs:     
Step 14: Configure Network Settings
Set public and cluster networks for optimal TB4 performance:

# Configure Ceph networks:
ssh n2 "ceph config set global public_network 10.11.12.0/24"
ssh n2 "ceph config set global cluster_network 10.100.0.0/24"

# Configure monitor networks:
ssh n2 "ceph config set mon public_network 10.11.12.0/24"
ssh n2 "ceph config set mon cluster_network 10.100.0.0/24"
Step 15: Create Additional Monitors
Create 3-monitor quorum on mesh nodes:

CLI Approach:

# Create monitor on n3:
ssh n3 "pveceph mon create"

# Create monitor on n4:
ssh n4 "pveceph mon create"
Expected output (for each):

Monitor daemon started successfully on node n3.
Monitor daemon started successfully on node n4.
GUI Approach:

n3: n3 node → Ceph → Monitor → "Create"
n4: n4 node → Ceph → Monitor → "Create"
Result: Green success messages on both nodes
Verify 3-monitor quorum:

ssh n2 "ceph quorum_status"
Expected output:

{
    "election_epoch": 3,
    "quorum": [
        0,
        1,
        2
    ],
    "quorum_names": [
        "n2",
        "n3",
        "n4"
    ],
    "quorum_leader_name": "n2",
    "quorum_age": 127,
    "monmap": {
        "epoch": 3,
        "fsid": "12345678-1234-5678-9abc-123456789abc",
        "modified": "2025-01-27T20:15:42.123456Z",
        "created": "2025-01-27T20:10:15.789012Z",
        "min_mon_release_name": "reef",
        "mons": [
            {
                "rank": 0,
                "name": "n2",
                "public_addrs": {
                    "addrvec": [
                        {
                            "type": "v2",
                            "addr": "10.11.12.12:3300"
                        }
                    ]
                }
            }
        ]
    }
}
What to verify:

3 monitors in quorum: "quorum_names": ["n2", "n3", "n4"]
All nodes listed: Should see all 3 mesh nodes
Leader elected: "quorum_leader_name" should show one of the nodes
Step 16: Create OSDs (2 per Node)
Create high-performance OSDs on NVMe drives:

CLI Approach:

# Create OSDs on n2:
ssh n2 "pveceph osd create /dev/nvme0n1"
ssh n2 "pveceph osd create /dev/nvme1n1"

# Create OSDs on n3:
ssh n3 "pveceph osd create /dev/nvme0n1"
ssh n3 "pveceph osd create /dev/nvme1n1"

# Create OSDs on n4:
ssh n4 "pveceph osd create /dev/nvme0n1"
ssh n4 "pveceph osd create /dev/nvme1n1"
Expected output (for each OSD):

Creating OSD on /dev/nvme0n1
OSD.0 created successfully.
OSD daemon started.
GUI Approach:

Location: Each node → Ceph → OSD → "Create: OSD"
Select: Choose /dev/nvme0n1 and /dev/nvme1n1 from device list
Advanced: Leave DB/WAL settings as default (co-located)
Result: Green "OSD created successfully" messages
Verify all OSDs are up:

ssh n2 "ceph osd tree"
Expected output:

ID CLASS WEIGHT  TYPE NAME     STATUS REWEIGHT PRI-AFF 
-1       5.45776 root default                          
-3       1.81959     host n2                           
 0   ssd 0.90979         osd.0     up  1.00000 1.00000 
 1   ssd 0.90979         osd.1     up  1.00000 1.00000 
-5       1.81959     host n3                           
 2   ssd 0.90979         osd.2     up  1.00000 1.00000 
 3   ssd 0.90979         osd.3     up  1.00000 1.00000 
-7       1.81959     host n4                           
 4   ssd 0.90979         osd.4     up  1.00000 1.00000 
 5   ssd 0.90979         osd.5     up  1.00000 1.00000 
What to verify:

6 OSDs total: 2 per mesh node (osd.0-5)
All 'up' status: Every OSD shows up in STATUS column
Weight 1.00000: All OSDs have full weight (not being rebalanced out)
Hosts organized: Each node (n2, n3, n4) shows as separate host with 2 OSDs
Phase 5: High-Performance Optimizations
Step 17: Memory Optimizations (64GB RAM Nodes)
Configure optimal memory usage for high-performance hardware:

# Set OSD memory target to 8GB per OSD (ideal for 64GB nodes):
ssh n2 "ceph config set osd osd_memory_target 8589934592"

# Set BlueStore cache sizes for NVMe performance:
ssh n2 "ceph config set osd bluestore_cache_size_ssd 4294967296"

# Set memory allocation optimizations:
ssh n2 "ceph config set osd osd_memory_cache_min 1073741824"
ssh n2 "ceph config set osd osd_memory_cache_resize_interval 1"
Step 18: CPU and Threading Optimizations (13th Gen Intel)
Optimize for high-performance CPUs:

# Set CPU threading optimizations:
ssh n2 "ceph config set osd osd_op_num_threads_per_shard 2"
ssh n2 "ceph config set osd osd_op_num_shards 8"

# Set BlueStore threading for NVMe:
ssh n2 "ceph config set osd bluestore_sync_submit_transaction false"
ssh n2 "ceph config set osd bluestore_throttle_bytes 268435456"
ssh n2 "ceph config set osd bluestore_throttle_deferred_bytes 134217728"

# Set CPU-specific optimizations:
ssh n2 "ceph config set osd osd_client_message_cap 1000"
ssh n2 "ceph config set osd osd_client_message_size_cap 1073741824"
Step 19: Network Optimizations for TB4 Mesh
Optimize network settings for TB4 high-performance cluster communication:

# Set network optimizations for TB4 mesh (65520 MTU, sub-ms latency):
ssh n2 "ceph config set global ms_tcp_nodelay true"
ssh n2 "ceph config set global ms_tcp_rcvbuf 134217728"
ssh n2 "ceph config set global ms_tcp_prefetch_max_size 65536"

# Set cluster network optimizations for 10.100.0.0/24 TB4 mesh:
ssh n2 "ceph config set global ms_cluster_mode crc"
ssh n2 "ceph config set global ms_async_op_threads 8"
ssh n2 "ceph config set global ms_dispatch_throttle_bytes 1073741824"

# Set heartbeat optimizations for fast TB4 network:
ssh n2 "ceph config set osd osd_heartbeat_interval 6"
ssh n2 "ceph config set osd osd_heartbeat_grace 20"
Step 20: BlueStore and NVMe Optimizations
Configure BlueStore for maximum NVMe and TB4 performance:

# Set BlueStore optimizations for NVMe drives:
ssh n2 "ceph config set osd bluestore_compression_algorithm lz4"
ssh n2 "ceph config set osd bluestore_compression_mode aggressive"
ssh n2 "ceph config set osd bluestore_compression_required_ratio 0.7"

# Set NVMe-specific optimizations:
ssh n2 "ceph config set osd bluestore_cache_trim_interval 200"

# Set WAL and DB optimizations for NVMe:
ssh n2 "ceph config set osd bluestore_block_db_size 5368709120"
ssh n2 "ceph config set osd bluestore_block_wal_size 1073741824"
Step 21: Scrubbing and Maintenance Optimizations
Configure scrubbing for high-performance environment:

# Set scrubbing optimizations:
ssh n2 "ceph config set osd osd_scrub_during_recovery false"
ssh n2 "ceph config set osd osd_scrub_begin_hour 2"
ssh n2 "ceph config set osd osd_scrub_end_hour 6"

# Set deep scrub optimizations:
ssh n2 "ceph config set osd osd_deep_scrub_interval 1209600"
ssh n2 "ceph config set osd osd_scrub_max_interval 1209600"
ssh n2 "ceph config set osd osd_scrub_min_interval 86400"

# Set recovery optimizations for TB4 mesh:
ssh n2 "ceph config set osd osd_recovery_max_active 8"
ssh n2 "ceph config set osd osd_max_backfills 4"
ssh n2 "ceph config set osd osd_recovery_op_priority 1"
Phase 6: Storage Pool Creation and Configuration
Step 22: Create High-Performance Storage Pool
Create optimized storage pool with 2:1 replication ratio:

# Create pool with optimal PG count for 6 OSDs (256 PGs = ~85 PGs per OSD):
ssh n2 "ceph osd pool create cephtb4 256 256"

# Set 2:1 replication ratio (size=2, min_size=1) for test lab:
ssh n2 "ceph osd pool set cephtb4 size 2"
ssh n2 "ceph osd pool set cephtb4 min_size 1"

# Enable RBD application for Proxmox integration:
ssh n2 "ceph osd pool application enable cephtb4 rbd"
Step 23: Verify Cluster Health
Check that cluster is healthy and ready:

ssh n2 "ceph -s"
Expected results:

Health: HEALTH_OK (or HEALTH_WARN with minor warnings)
OSDs: 6 osds: 6 up, 6 in
PGs: All PGs active+clean
Pools: cephtb4 pool created and ready
Phase 7: Performance Testing and Validation
Step 24: Test Optimized Cluster Performance
Run comprehensive performance testing to validate optimizations:

# Test write performance with optimized cluster:
ssh n2 "rados -p cephtb4 bench 10 write --no-cleanup -b 4M -t 16"

# Test read performance:
ssh n2 "rados -p cephtb4 bench 10 rand -t 16"

# Clean up test data:
ssh n2 "rados -p cephtb4 cleanup"
Results

Write Performance:

Average Bandwidth: 1,294 MB/s
Peak Bandwidth: 2,076 MB/s
Average IOPS: 323
Average Latency: ~48ms
Read Performance:

Average Bandwidth: 1,762 MB/s
Peak Bandwidth: 2,448 MB/s
Average IOPS: 440
Average Latency: ~36ms
Step 25: Verify Configuration Database
Check that all optimizations are active in Proxmox GUI:

Navigate: Ceph → Configuration Database
Verify: All optimization settings visible and applied
Check: No configuration errors or warnings
Key optimizations to verify:

osd_memory_target: 8589934592 (8GB per OSD)
bluestore_cache_size_ssd: 4294967296 (4GB cache)
bluestore_compression_algorithm: lz4
cluster_network: 10.100.0.0/24 (TB4 mesh)
public_network: 10.11.12.0/24
Troubleshooting Common Issues
TB4 Mesh Issues
Problem: TB4 interfaces not coming up after reboot Root Cause: Udev rules may not trigger on boot, scripts may be corrupted

Quick Fix: Manually bring up interfaces:

# Solution: Manually bring up interfaces and reapply SDN config:
for node in n2 n3 n4; do
  ssh $node "ip link set en05 up mtu 65520"
  ssh $node "ip link set en06 up mtu 65520"
  ssh $node "ifreload -a"
done
Permanent Fix: Check systemd service and scripts:

# Verify systemd service is enabled:
for node in n2 n3 n4; do
  ssh $node "systemctl status thunderbolt-interfaces.service"
done

# Check if scripts are corrupted (should be ~13 lines, not 31073):
for node in n2 n3 n4; do
  ssh $node "wc -l /usr/local/bin/pve-en*.sh"
done

# Check for shebang errors:
for node in n2 n3 n4; do
  ssh $node "head -1 /usr/local/bin/*.sh | grep -E 'thunderbolt|pve-en'"
done
# If you see #\!/bin/bash (with backslash), fix it:
for node in n2 n3 n4; do
  ssh $node "sed -i '1s/#\\\\!/#!/' /usr/local/bin/thunderbolt-startup.sh"
  ssh $node "sed -i '1s/#\\\\!/#!/' /usr/local/bin/pve-en05.sh"
  ssh $node "sed -i '1s/#\\\\!/#!/' /usr/local/bin/pve-en06.sh"
done
Problem: Systemd service fails with "Exec format error"

Root Cause: Corrupted shebang line in scripts (#!/bin/bash instead of #!/bin/bash)
Diagnosis: Check systemctl status thunderbolt-interfaces for exec format errors
Solution: Fix shebang lines as shown above, then restart service
Problem: Mesh connectivity fails between some nodes

# Check interface status:
for node in n2 n3 n4; do
  echo "=== $node TB4 status ==="
  ssh $node "ip addr show | grep -E '(en05|en06|10\.100\.0\.)'"
done

# Verify FRR routing service:
for node in n2 n3 n4; do
  ssh $node "systemctl status frr"
done
Ceph Issues
Problem: OSDs going down after creation

Root Cause: Usually network connectivity issues (TB4 mesh not working)
Solution: Fix TB4 mesh first, then restart OSD services:
# Restart OSD services after fixing mesh:
for node in n2 n3 n4; do
  ssh $node "systemctl restart ceph-osd@*.service"
done
Problem: Ceph cluster shows OSDs down after reboot

Symptoms: ceph status shows OSDs down, heartbeat failures in logs
Root Cause: TB4 interfaces (Ceph private network) not coming up
Solution:
# 1. Bring up TB4 interfaces on all nodes:
for node in n2 n3 n4; do
  ssh $node "/usr/local/bin/pve-en05.sh"
  ssh $node "/usr/local/bin/pve-en06.sh"
done

# 2. Wait for interfaces to stabilize:
sleep 10

# 3. Restart Ceph OSDs:
for node in n2 n3 n4; do
  ssh $node "systemctl restart ceph-osd@*.service"
done

# 4. Monitor recovery:
ssh n2 "watch ceph -s"
Problem: Inactive PGs or slow performance

# Check cluster status:
ssh n2 "ceph -s"

# Verify optimizations are applied:
ssh n2 "ceph config dump | grep -E '(memory_target|cache_size|compression)'"

# Check network binding:
ssh n2 "ceph config get osd cluster_network"
ssh n2 "ceph config get osd public_network"
Problem: Proxmox GUI doesn't show OSDs

Root Cause: Usually config database synchronization issues
Solution: Restart Ceph monitor services and check GUI again
System-Level Performance Optimizations (Optional)
Additional OS-Level Tuning
For even better performance on high-end hardware:

# Apply on all mesh nodes:
for node in n2 n3 n4; do
  ssh $node "
    # Network tuning:
    echo 'net.core.rmem_max = 268435456' >> /etc/sysctl.conf
    echo 'net.core.wmem_max = 268435456' >> /etc/sysctl.conf
    echo 'net.core.netdev_max_backlog = 30000' >> /etc/sysctl.conf
    
    # Memory tuning:
    echo 'vm.swappiness = 1' >> /etc/sysctl.conf
    echo 'vm.min_free_kbytes = 4194304' >> /etc/sysctl.conf
    
    # Apply settings:
    sysctl -p
  "
done
Changelog
July 30, 2025
Added troubleshooting for "Exec format error" caused by corrupted shebang lines
Fixed script examples to ensure proper shebang format (#!/bin/bash)
Added diagnostic commands for detecting shebang corruption
July 28, 2025
Initial complete guide created
Integrated TB4 mesh networking with Ceph storage
Added systemd service for boot reliability
Comprehensive troubleshooting section
Load earlier comments...
@taslabs-net
Author
taslabs-net
commented
on Nov 19, 2025
Network/Messaging tuning:

ms_async_op_threads: 8
ms_dispatch_throttle_bytes: 1GB
ms_tcp_nodelay: true
ms_tcp_rcvbuf: 128MB
BlueStore tuning:

bluestore_cache_size_ssd: 4GB
bluestore_compression_algorithm: lz4
bluestore_compression_mode: aggressive
bluestore_block_db_size: 5GB
bluestore_block_wal_size: 1GB
OSD tuning:

osd_op_num_shards: 8
osd_op_num_threads_per_shard: 2
osd_memory_target: 12GB
osd_recovery_op_priority: 1
@Allistah
Allistah
commented
on Nov 19, 2025
Awesome, thank you! What kind of speeds do you get in general for Ceph performance? I wasn't about to get any more than about 175 MB/s write. Not sure why.. The NVMe drives are super fast, the network they're on is super fast (26 Gb/s) and these are Intel NUC 13 Pros so they've got a lot of CPU power available.

Do you run any benchmarks at all on Ceph? If so, what is the command you run to benchmark your Ceph setup? TIA!

@taslabs-net
Author
taslabs-net
commented
on Nov 19, 2025
The current TB4 networking stack only allows for single queue. So you can't take advantage yet of the multiqueing. Maybe in TB4v2 or TB5? I can't confirm. But it's either a TB4 limitation on the domain pathing with concurrent routes to the same net, or if it's capable it's a module update for the kernel driver?

Also remember metadata/small files will always add overhead and will write much much slower because of design.

@pSyCr0
pSyCr0
commented
on Nov 20, 2025
Are your nodes part of a cluster? You'll need to get them configured that way before they will show up in the "Add node" dropdown for the Fabric config.

That's true to use the PVE interface. I created my CEPH cluster not to be dependent on the PVE cluster UI at the time, since it was in beta.

So I have to get them in a cluster over the normal 2.5Gbit interfaces to configure this part of the instruction?

@taslabs-net
Author
taslabs-net
commented
on Nov 20, 2025
• 
Common misconception.

3 networks involved in my specific setup

mgmt network (vmbr0 pve cluster)
vm network (vmbr1 vm traffic)
tb4 network (ceph private network)
PVE Cluster does not equal Ceph Cluster. They are completely separate. However, it can get "combined" if you use Ceph on the same network as the PVE cluster if that makes sense? So in my specific setup, I "PVE Cluster" on one of the 2.5's. But the CEPH Cluster is over tb4. So.. that means the ceph private network (so ceph cluster traffic only) is on the tb4 ports, the ceph public network is the same network i use for my vm's.

does that help?

Edit: my setup (at least the part of the cluster that matters)

3 x MS01's

10gbe x 2 (ipv4/6) are LACP together at the switch and in PVE - CEPH Public network & PVE primary vm network (so Plex, *arr, caddy/zoraxy thanks @tobychui, etc etc) PVE backup mgmt network
2.5gbe x 1 (ipv4) is PVE primary mgmt network (vm migrations, pbs etc, network mgmt vlan etc)
2.5gbe x 1 (ipv4/6) testing network with either Cloudflare layer3 gre/ipsec stuff or unused or whatever is needed

tb4 x 2 en05/06 ceph cluster private network

@taslabs-net
Author
taslabs-net
commented
on Nov 20, 2025
@Allistah i ran some for you today

i stood up a standard debian13 lxc, you could use helper scripts and it works fine, but give it a decent drive. i did 25g which was fine becuse i also turned it into my database server for later. I gave it .5/24 for testing grab fio apt-get install fio

and then i ran:

Test 1: Random 4K Read/Write
Command:

fio --name=random-rw --ioengine=libaio --rw=randrw --rwmixread=70 \
    --bs=4k --direct=1 --size=1G --numjobs=4 --runtime=30 \
    --time_based --group_reporting --filename=/tmp/test.fio
Results:

Read: 840,000 IOPS / 3,280 MB/s
Write: 360,000 IOPS / 1,405 MB/s
Latency (P50/P95): Read: 294ns/612ns, Write: 294ns/628ns
Test 2: Sequential Write
Command:

fio --name=seq-write --ioengine=libaio --rw=write --bs=1M \
    --direct=1 --size=2G --numjobs=1 --runtime=30 \
    --time_based --group_reporting --filename=/tmp/test-seq.fio
Results:

Write: 10,400 IOPS / 10.2 GB/s
Latency (P50/P95): 446ns/620ns
Test 3: Sequential Read
Command:

fio --name=seq-read --ioengine=libaio --rw=read --bs=1M \
    --direct=1 --size=2G --numjobs=1 --runtime=30 \
    --time_based --group_reporting --filename=/tmp/test-seq.fio
Results:

Read: 11,700 IOPS / 11.4 GB/s
Latency (P50/P95): 470ns/652ns
Test 4: Database Workload Simulation
Command:

fio --name=db-workload --ioengine=libaio --rw=randrw --rwmixread=80 \
    --bs=8k --direct=1 --size=5G --numjobs=8 --iodepth=32 \
    --runtime=30 --time_based --group_reporting --filename=/var/lib/test-db.fio
Results:

Read: 12,400 IOPS / 97.2 MB/s
Write: 3,122 IOPS / 24.4 MB/s
Latency P50: Read: 676μs, Write: 10ms
Latency P95: Read: 210ms, Write: 224ms
Latency P99: Read: 250ms, Write: 266ms
those high numbers are the direct result of the bluestore and caching etc (the entire point)

um make sure you clean stuff up when you're done..

/tmp/test.fio
/tmp/test-seq.fio
/var/lib/test-db.fio

@Allistah
Allistah
commented
on Nov 20, 2025
I figured out the issue. The issue is with Ceph's config. I had the Ceph "Public" network set to my 1 Gb/s network and the Ceph "Cluster" network set to the Thunderbolt network. This was causing a massive bottleneck in the Ceph traffic as part of it was having to go through the slow 1 GB/s link. I do not use Ceph storage at all so once I set both the Ceph Public and Ceph Cluster network to use the Thunderbolt network, then everything exploded and is super fast. Now I get about 1.3 GB/s which is what I would expect. Hope this helps someone else!

@Allistah
Allistah
commented
on Nov 20, 2025
@Allistah i ran some for you today

i stood up a standard debian13 lxc, you could use helper scripts and it works fine, but give it a decent drive. i did 25g which was fine becuse i also turned it into my database server for later. I gave it .5/24 for testing grab fio apt-get install fio

Nice! See my previous post - I figured out why I was capped at ~175 MB/s. I had the Ceph Public and Ceph Cluster network set wrong. Once I changed the Ceph Public network over to the Thunderbolt network, I started getting 1.3 GB/s throughput on writes. Also now that you've given me some benchmark lines, I'll run some of those and see what results I get now that things are fixed. I'll get back with some results - tomorrow probably.

@Allistah
Allistah
commented
on Nov 21, 2025
@Allistah i ran some for you today

fio --name=random-rw --ioengine=libaio --rw=randrw --rwmixread=70 \
    --bs=4k --direct=1 --size=1G --numjobs=4 --runtime=30 \
    --time_based --group_reporting --filename=/tmp/test.fio
What Helper script did you use to test this? I'd like to try the same thing. I used a Debian 13 one but the write tests crash when using /tmp and its something to do with it being a ram /tmp and ChatGPT said I need to use a real disk location like /root or something.

Can you tell me which LXC you've got and which script it came from?

@taslabs-net
Author
taslabs-net
commented
on Nov 21, 2025
Oh i'm not using a helper script. I mean you can use theirs to install the lxc or vm for testing. use their debian 13 lxc would be the easiest. then make sure you install fio and you should be good?

@Allistah
Allistah
commented
on Nov 21, 2025
Ah ok, you made it yourself. I’ll try that. For some reason, the writes to /tmp broke it and ended up crashing the host believe it or not. I’ll try a fresh LXC and try again using your exact commands with fio and get back to you.

@taslabs-net
Author
taslabs-net
commented
on Nov 21, 2025
That’s def odd.

@pSyCr0
pSyCr0
commented
on Nov 21, 2025
• 
Strange interface error which I have now... Yesterday I had only ipv4 ip adresses on the en05/06 and now only ipv6. What has now to be written in den interface config. In the first part of the config is described that I need to set ipv4 adresses on each en05/06 interface and on the second part nothing about that. Mine looks like this on the second node:

`auto lo
iface lo inet loopback

iface enp86s0 inet manual

auto vmbr0
iface vmbr0 inet static
        address 192.168.1.92/24
        gateway 192.168.1.1
        bridge-ports enp86s0
        bridge-stp off
        bridge-fd 0

iface en05 inet manual #do not edit in GUI
iface en06 inet manual #do not edit in GUI

auto en05
iface en05 inet static
    address 10.100.0.6/30
    mtu 65520

auto en06
iface en06 inet static
    address 10.100.0.9/30
    mtu 65520

source /etc/network/interfaces.d/

root@pve2:~# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute 
       valid_lft forever preferred_lft forever
2: enp86s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq master vmbr0 state UP group default qlen 1000
    link/ether 48:21:0b:56:08:69 brd ff:ff:ff:ff:ff:ff
    altname enx48210b560869
3: vmbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000    link/ether 48:21:0b:56:08:69 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.92/24 scope global vmbr0
       valid_lft forever preferred_lft forever
    inet6 fe80::4a21:bff:fe56:869/64 scope link proto kernel_ll 
       valid_lft forever preferred_lft forever
4: en05: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65520 qdisc fq_codel state UP group default qlen 1000
    link/ether 02:64:9e:4e:f6:62 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::64:9eff:fe4e:f662/64 scope link proto kernel_ll 
       valid_lft forever preferred_lft forever
5: en06: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65520 qdisc fq_codel state UP group default qlen 1000
    link/ether 02:28:b7:60:f6:af brd ff:ff:ff:ff:ff:ff
    inet6 fe80::28:b7ff:fe60:f6af/64 scope link proto kernel_ll 
       valid_lft forever preferred_lft forever*`
Is this correct?

@taslabs-net
Author
taslabs-net
commented
on Nov 21, 2025
yes, that looks correct I think. did you ifreload -a

@ikiji-ns
ikiji-ns
commented
on Nov 25, 2025
• 
Hi @taslabs-net,

Great article, and thanks for sharing.
Completely new to Proxmox and CephFS, so my apologies in advance for what may appear obvious to others but can I ask, regarding the TB4, point-to-point setup, what is the need for SDN setup when this is purely for the private Ceph cluster?

I have the IPv4 working via /31's with the following config:

pve01

iface en05 inet manual
#do not edit it GUI

iface en06 inet manual
#do not edit in GUI

# --- Thunderbolt mesh links (P2P /31s) ---
# en05 → pve02 (Link A, 10.100.0.0/31)
#   pve01: 10.100.0.0/31   <->   pve02: 10.100.0.1/31
auto en05
iface en05 inet static
    address 10.100.0.0/31
    mtu 65520

# en06 → pve03 (Link C, 10.100.0.4/31)
#   pve01: 10.100.0.4/31   <->   pve03: 10.100.0.5/31
auto en06
iface en06 inet static
    address 10.100.0.4/31
    mtu 65520
pve02

iface en05 inet manual
#do not edit it GUI

iface en06 inet manual
#do not edit in GUI

# --- Thunderbolt mesh links (P2P /31s) ---
# en05 → pve01 (Link A, 10.100.0.0/31)
#   pve02: 10.100.0.1/31   <->   pve01: 10.100.0.0/31
auto en05
iface en05 inet static
    address 10.100.0.1/31
    mtu 65520

# en06 → pve03 (Link B, 10.100.0.2/31)
#   pve02: 10.100.0.2/31   <->   pve03: 10.100.0.3/31
auto en06
iface en06 inet static
    address 10.100.0.2/31
    mtu 65520
pve03

iface en05 inet manual
#do not edit it GUI

iface en06 inet manual
#do not edit in GUI

# --- Thunderbolt mesh links (P2P /31s) ---
# en05 → pve02 (Link B, 10.100.0.2/31)
#   pve03: 10.100.0.3/31   <->   pve02: 10.100.0.2/31
auto en05
iface en05 inet static
    address 10.100.0.3/31
    mtu 65520

# en06 → pve01 (Link C, 10.100.0.4/31)
#   pve03: 10.100.0.5/31   <->   pve01: 10.100.0.4/31
auto en06
iface en06 inet static
    address 10.100.0.5/31
    mtu 65520
I can do the following pings:

# pve01
ping -c3 10.100.0.1   # → pve02
ping -c3 10.100.0.5   # → pve03

# pve02
ping -c3 10.100.0.0   # → pve01
ping -c3 10.100.0.3   # → pve03

# pve03
ping -c3 10.100.0.2   # → pve02
ping -c3 10.100.0.4   # → pve01
Really wanted to sanity check that I'm not missing something re: SDN, as figured we didn't need bridges, VNETs, EVPN, extra routes etc?

Likewise, do we need the following for the Ceph private mesh network?

net.ipv4.ip_forward = 1
Thanks

@taslabs-net
Author
taslabs-net
commented
on Nov 26, 2025
Technically speaking there is no need whatsoever. That way you have it working without SDN is the traditional way you'd need to do it. PVE9 introduced the ability to bring it "into the ui" . Sort of.. so I did CLI to get it working and have been slowly trying to answer questions about the UI? but I think some others have more updated versions with just UI maybe?

@scloder
scloder
commented
on Dec 5, 2025
• 
after reboot I always have to use the UI SDN to Apply the fabric again, but generally it’s working.
I went with the method to not use the /30 networks.

/etc/network/interfaces

auto lo
iface lo inet loopback

auto en05
iface en05 inet manual
    mtu 65520

auto en06
iface en06 inet manual
    mtu 65520

# ...

source /etc/network/interfaces.d/*
/etc/network/interfaces.d/sdn

#version:59

auto dummy_tb4
iface dummy_tb4 inet static
    address 10.101.0.1/32
    link-type dummy
    ip-forward 1

auto en05
iface en05 inet static
    address 10.101.0.1/32
    ip-forward 1

auto en06
iface en06 inet static
    address 10.101.0.1/32
    ip-forward 1
Still unsure why I need to Apply SDN after every reboot.

@aelhusseiniakl
aelhusseiniakl
commented
on Dec 5, 2025
in MS-01 and proxmox 9.1.1 thunderbolt interfaces appears under network directly why i still need two en05 & en06 does it's required to link ip address?

@taslabs-net
Author
taslabs-net
commented
on Dec 5, 2025
in MS-01 and proxmox 9.1.1 thunderbolt interfaces appears under network directly why i still need two en05 & en06 does it's required to link ip address?

maybe you don't, have you tried?

@aelhusseiniakl
aelhusseiniakl
commented
on Dec 6, 2025
Yes, I’ve tried it, and the ports were detected during the initial Proxmox installation. If the cables are not connected at that stage, the interfaces will not appear later even if you plug them in afterward.

@aelhusseiniakl
aelhusseiniakl
commented
on Dec 6, 2025
The following is a secreanshot after clean installation of PVE 9.1.1
image

@taslabs-net
Author
taslabs-net
commented
on Dec 11, 2025
I stepped away for a bit. Did you get it settled?

@aelhusseiniakl
aelhusseiniakl
commented
on Dec 11, 2025
Yes i did, and i post the full steps in gist if you want i can post the link

@taslabs-net
Author
taslabs-net
commented
on Dec 11, 2025
Yes i did, and i post the full steps in gist if you want i can post the link

man link it up! this is a community to help. i know my directions might be a little out of date. i've had my cluster running since 4 days after pve9 beta was released. so it's gone through a ton of changes. My directions are bound to need updating. I was thinking of making it part of my repo (i contribute to a few on different accounts) and we can keep it updated?

@aelhusseiniakl
aelhusseiniakl
commented
on Dec 12, 2025
Thanks for your kind words! I actually came across your post earlier while I was trying to understand why the Thunderbolt interfaces were appearing automatically in my setup. I'm currently working as a Senior Consultant, and I always enjoy deep-diving into the technology to understand how things behave under the hood.
My steps may still be missing something, but I’m sharing them in case they help others—and I’d be more than happy to hear any comments, suggestions, or advice you might have.
here is the link: https://gist.github.com/aelhusseiniakl/39e3fd9f29abda6153a3b5a0a5bc191b#configure-ceph-in-proxmox-9-easy-way-as-you-never-did-before

@Allistah
Allistah
commented
on Dec 12, 2025
• 
I followed a good number of these steps when I had to recently flatten all three of my nodes and reinstall Proxmox 9.1 from scratch. It helped a lot but there were for sure some things that I did differently. One thing that comes to mind that wasn't working for me the way it was set up in this Gist is the way the IPs for the Thunderbolt are set up.

This is what I have mine set up and it works very well with 9.1:

Node1:
10.0.0.1/32 - en05 (Port 1) --> en06 (Node 2, Port 2) 10.0.0.4
10.0.0.2/32 - en06 (Port 2) --> en05 (Node 3, Port 1) 10.0.0.5
10.0.0.101/32 - dummy_TB4 interface

Node2:
10.0.0.3/32 - en05 (Port 1) --> en05 (Node 3, Port 2) 10.0.0.6
10.0.0.4/32 - en06 (Port 2) --> en06 (Node 1, Port 1) 10.0.0.1
10.0.0.102/32 - dummy_TB4 interface

Node3:
10.0.0.5/32 - en05 (Port 1) --> en05 (Node 1, Port 2) 10.0.0.2
10.0.0.6/32 - en06 (Port 2) --> en06 (Node 2, Port 1) 10.0.0.3
10.0.0.103/32 - dummy_TB4 interface

Here is a copy of the /etc/pve/datacenter.cfg

keyboard: en-us
migration: network=10.0.0.96/28,type=insecure
replication: network=10.0.0.96/28,type=insecure

This is important because 10.0.0.96/28 covers the following network:
Network Address: 10.0.0.96
Usable Host IP Range: 10.0.0.97 - 10.0.0.110
Broadcast Address: 10.0.0.111

This 10.0.0.96/28 subnet covers all of the dummy_TB4 addresses which are .101, .102, and .103. This is what made it all work great for me. I feel like these are simplified with the numbering as well. If I used anything but /32 on the TB4 ports, it caused communication problems between the nodes.

Here is a copy of the /etc/network/interfaces from Node 1:
auto lo
iface lo inet loopback

auto vmbr0
iface vmbr0 inet static
address 10.61.30.21/24
gateway 10.61.30.1
bridge-ports nic0
bridge-stp off
bridge-fd 0
bridge-vlan-aware yes
bridge-vids 10 20 30

auto dummy_TB4
iface dummy_TB4 inet static
address 10.0.0.101/32
link-type dummy
mtu 65520
ip-forward 1

allow-hotplug en05
iface en05 inet static
address 10.0.0.1/32
mtu 65520
ip-forward 1

allow-hotplug en06
iface en06 inet static
address 10.0.0.2/32
mtu 65520
ip-forward 1

#source /etc/network/interfaces.d/*

Let me know if there are any other files that you'd be interested in seeing. I am using the SDN/Fabrics from the GUI as well. I get a very consistent 26 Gb/s on all TB4 ports using iperf3 and when I run live migrations, it transfers the memory snapshots close to 3 GB/s which is blazingly fast. I'd love to contribute to making this Gist better so that others can use it so please let me know how I can help. Would be cool to come up with some standard with the current versions of Proxmox to get this set up.

@Yearly1825
Yearly1825
commented
11 hours ago
Thanks for your kind words! I actually came across your post earlier while I was trying to understand why the Thunderbolt interfaces were appearing automatically in my setup. I'm currently working as a Senior Consultant, and I always enjoy deep-diving into the technology to understand how things behave under the hood. My steps may still be missing something, but I’m sharing them in case they help others—and I’d be more than happy to hear any comments, suggestions, or advice you might have. here is the link: https://gist.github.com/aelhusseiniakl/39e3fd9f29abda6153a3b5a0a5bc191b#configure-ceph-in-proxmox-9-easy-way-as-you-never-did-before

So I had previously followed @taslabs-net guide from this gist and it worked great. I was in a position to freshly flash a new cluster so came back to this guide to check out the changes and ended up following the guide by @aelhusseiniakl just to test the GUI only setup and it worked well. Everything set through the GUI. I kept the MTU 65520 from the @taslabs-net guide.

The only issue I have found with the @aelhusseiniakl guide is thunderbolt interfaces coming up on reboot/hotplug. During boot the thunderbolt is recognized a few seconds after the network stack loads, so even checking "automatic" in the node's network interfaces has no effect.

Claude remedied that with the following script that combines the udev fix from @taslabs-net guide with a systemd service to have ceph and frr wait on thunderbolt on boot. So far it has been working great. I figured I'd post this in here as another data point. This was done on three MS-01 cluster, flashed with the latest proxmox installer and updated to the latest version 9.1.4.

cat > /root/setup-thunderbolt-boot.sh << 'SCRIPT'
#!/bin/bash
# Thunderbolt Network Boot Fix for Proxmox 9 + SDN OpenFabric
# Run this script on each node (node0, node1, node2)

set -e

echo "=== Setting up Thunderbolt network boot fix ==="

# 1. Create udev rules
echo "Creating udev rules..."
cat > /etc/udev/rules.d/10-thunderbolt-net.rules << 'EOF'
# Bring up Thunderbolt network interfaces when they appear (boot + hot-plug)
ACTION=="add", SUBSYSTEM=="net", KERNEL=="thunderbolt0", RUN+="/usr/local/bin/pve-thunderbolt0.sh"
ACTION=="add", SUBSYSTEM=="net", KERNEL=="thunderbolt1", RUN+="/usr/local/bin/pve-thunderbolt1.sh"
EOF

# 2. Create interface scripts with retry logic
echo "Creating interface scripts..."
cat > /usr/local/bin/pve-thunderbolt0.sh << 'EOF'
#!/bin/bash
LOGFILE="/var/log/thunderbolt-network.log"
IF="thunderbolt0"

echo "$(date): pve-$IF.sh triggered by udev" >> "$LOGFILE"
sleep 2

for i in {1..10}; do
    echo "$(date): Attempt $i to bring up $IF" >> "$LOGFILE"
    /usr/sbin/ifup "$IF" >> "$LOGFILE" 2>&1 && {
        echo "$(date): Successfully brought up $IF on attempt $i" >> "$LOGFILE"
        exit 0
    }
    echo "$(date): Attempt $i failed, retrying..." >> "$LOGFILE"
    sleep 2
done
echo "$(date): FAILED to bring up $IF after 10 attempts" >> "$LOGFILE"
EOF

cat > /usr/local/bin/pve-thunderbolt1.sh << 'EOF'
#!/bin/bash
LOGFILE="/var/log/thunderbolt-network.log"
IF="thunderbolt1"

echo "$(date): pve-$IF.sh triggered by udev" >> "$LOGFILE"
sleep 2

for i in {1..10}; do
    echo "$(date): Attempt $i to bring up $IF" >> "$LOGFILE"
    /usr/sbin/ifup "$IF" >> "$LOGFILE" 2>&1 && {
        echo "$(date): Successfully brought up $IF on attempt $i" >> "$LOGFILE"
        exit 0
    }
    echo "$(date): Attempt $i failed, retrying..." >> "$LOGFILE"
    sleep 2
done
echo "$(date): FAILED to bring up $IF after 10 attempts" >> "$LOGFILE"
EOF

chmod +x /usr/local/bin/pve-thunderbolt0.sh
chmod +x /usr/local/bin/pve-thunderbolt1.sh

# 3. Create systemd service for boot ordering (ensures Ceph waits)
echo "Creating systemd service..."
cat > /etc/systemd/system/thunderbolt-network.service << 'EOF'
[Unit]
Description=Thunderbolt network interfaces ready
After=sys-subsystem-net-devices-thunderbolt0.device sys-subsystem-net-devices-thunderbolt1.device
Wants=sys-subsystem-net-devices-thunderbolt0.device sys-subsystem-net-devices-thunderbolt1.device
Before=ceph.target frr.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'for i in {1..60}; do ip link show thunderbolt0 2>/dev/null | grep -q "state UP" && ip link show thunderbolt1 2>/dev/null | grep -q "state UP" && echo "Thunderbolt interfaces ready" && exit 0; sleep 1; done; echo "Warning: Thunderbolt interfaces not ready after 60s"; exit 0'

[Install]
WantedBy=multi-user.target
EOF

# 4. Reload and enable everything
echo "Activating configuration..."
systemctl daemon-reload
systemctl enable thunderbolt-network.service
udevadm control --reload-rules

# 5. Initialize log file
touch /var/log/thunderbolt-network.log

echo ""
echo "=== Setup complete on $(hostname)! ==="
echo ""
SCRIPT
@taslabs-net
Author
taslabs-net
commented
10 hours ago
@Yearly1825 thanks for posting! I did plan on making this a repo. and still might. ive set up a few now and have it down to a few small install scripts. i'll get to posting it soon for anyone that comes along later. Thank you :)

@corvy
corvy
commented
10 hours ago
Maybe we should make this into a simple ansible playbook? I have been thinking about that to be able to audit my settings and configuration, also that would make it simpler in case a node needs to be rebuilt for any reason.

@Yearly1825
Yearly1825
commented
1 hour ago
• 
@taslabs-net A repo would be nice, then we could keep it up to date as this develops. It also will help as proxmox 10 comes out in the future and we are all looking for the latest and greatest. Plus it could link the previous well used guides.

@corvy I almost went down this route before, but then though "how many times would I use it", and then I have flashed a cluster about 10 times. So I dont think this is a bad idea either. Would keep an audit trail of everything and could use templates for the systemd units. Plus have checks for things that are MS-01 specific, etc.

So one thing to add. I had a power outage so all MS-01's obviously went down and had to boot at the same time. Well that creates an issue where there aren't thunderbolt links to trigger thunderbolt/thunderbolt_net to load (if there's no link detected). So to fix I added the following.

cat > /etc/modules-load.d/thunderbolt.conf << 'EOF'
thunderbolt
thunderbolt_net
EOF
So final updated script (from what I posted three posts up and this fix is the following):

cat > /root/setup-thunderbolt-boot.sh << 'SCRIPT'
#!/bin/bash
# Thunderbolt Network Boot Fix for Proxmox 9 + SDN OpenFabric
# Run this script on each node (node0, node1, node2)

set -e

echo "=== Setting up Thunderbolt network boot fix ==="

# 1. Ensure kernel modules load early
echo "Configuring kernel modules..."
cat > /etc/modules-load.d/thunderbolt.conf << 'EOF'
thunderbolt
thunderbolt_net
EOF

# 2. Create udev rules
echo "Creating udev rules..."
cat > /etc/udev/rules.d/10-thunderbolt-net.rules << 'EOF'
# Bring up Thunderbolt network interfaces when they appear (boot + hot-plug)
ACTION=="add", SUBSYSTEM=="net", KERNEL=="thunderbolt0", RUN+="/usr/local/bin/pve-thunderbolt0.sh"
ACTION=="add", SUBSYSTEM=="net", KERNEL=="thunderbolt1", RUN+="/usr/local/bin/pve-thunderbolt1.sh"
EOF

# 3. Create interface scripts with retry logic
echo "Creating interface scripts..."
cat > /usr/local/bin/pve-thunderbolt0.sh << 'EOF'
#!/bin/bash
LOGFILE="/var/log/thunderbolt-network.log"
IF="thunderbolt0"

echo "$(date): pve-$IF.sh triggered by udev" >> "$LOGFILE"
sleep 2

for i in {1..10}; do
    echo "$(date): Attempt $i to bring up $IF" >> "$LOGFILE"
    /usr/sbin/ifup "$IF" >> "$LOGFILE" 2>&1 && {
        echo "$(date): Successfully brought up $IF on attempt $i" >> "$LOGFILE"
        exit 0
    }
    echo "$(date): Attempt $i failed, retrying..." >> "$LOGFILE"
    sleep 2
done
echo "$(date): FAILED to bring up $IF after 10 attempts" >> "$LOGFILE"
EOF

cat > /usr/local/bin/pve-thunderbolt1.sh << 'EOF'
#!/bin/bash
LOGFILE="/var/log/thunderbolt-network.log"
IF="thunderbolt1"

echo "$(date): pve-$IF.sh triggered by udev" >> "$LOGFILE"
sleep 2

for i in {1..10}; do
    echo "$(date): Attempt $i to bring up $IF" >> "$LOGFILE"
    /usr/sbin/ifup "$IF" >> "$LOGFILE" 2>&1 && {
        echo "$(date): Successfully brought up $IF on attempt $i" >> "$LOGFILE"
        exit 0
    }
    echo "$(date): Attempt $i failed, retrying..." >> "$LOGFILE"
    sleep 2
done
echo "$(date): FAILED to bring up $IF after 10 attempts" >> "$LOGFILE"
EOF

chmod +x /usr/local/bin/pve-thunderbolt0.sh
chmod +x /usr/local/bin/pve-thunderbolt1.sh

# 4. Create systemd service for boot ordering (ensures Ceph waits)
echo "Creating systemd service..."
cat > /etc/systemd/system/thunderbolt-network.service << 'EOF'
[Unit]
Description=Thunderbolt network interfaces ready
After=sys-subsystem-net-devices-thunderbolt0.device sys-subsystem-net-devices-thunderbolt1.device
Wants=sys-subsystem-net-devices-thunderbolt0.device sys-subsystem-net-devices-thunderbolt1.device
Before=ceph.target frr.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'for i in {1..60}; do ip link show thunderbolt0 2>/dev/null | grep -q "state UP" && ip link show thunderbolt1 2>/dev/null | grep -q "state UP" && echo "Thunderbolt interfaces ready" && exit 0; sleep 1; done; echo "Warning: Thunderbolt interfaces not ready after 60s"; exit 0'

[Install]
WantedBy=multi-user.target
EOF

# 5. Reload and enable everything
echo "Activating configuration..."
systemctl daemon-reload
systemctl enable thunderbolt-network.service
udevadm control --reload-rules

# 6. Initialize log file
touch /var/log/thunderbolt-network.log

echo ""
echo "=== Setup complete on $(hostname)! ==="
echo ""
echo "Files created:"
echo "  /etc/modules-load.d/thunderbolt.conf"
echo "  /etc/udev/rules.d/10-thunderbolt-net.rules"
echo "  /usr/local/bin/pve-thunderbolt0.sh"
echo "  /usr/local/bin/pve-thunderbolt1.sh"
echo "  /etc/systemd/system/thunderbolt-network.service"
echo ""
SCRIPT