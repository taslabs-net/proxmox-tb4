# SSH Setup

Before running any automation, you need passwordless SSH access from your workstation to all nodes.

## Why This Matters

All the scripts in this guide run commands on multiple nodes. Without passwordless SSH:
- You'd have to type passwords repeatedly
- Scripts can't run non-interactively
- Automation becomes impossible

## Automated Setup

The easiest way is to use the provided script:

```bash
# From your workstation
./scripts/01-setup-ssh.sh
```

This script will:
1. Generate an SSH key if you don't have one
2. Accept host keys from all nodes
3. Deploy your public key to each node
4. Test the connection

## Manual Setup

If you prefer to do it manually:

### Step 1: Generate SSH Key (If Needed)

```bash
# Check if you already have a key
ls -la ~/.ssh/id_ed25519

# If not, generate one
ssh-keygen -t ed25519 -C "proxmox-tb4-cluster" -f ~/.ssh/id_ed25519
```

**Note:** Ed25519 keys are recommended over RSA for modern systems.

### Step 2: Accept Host Keys

The first time you SSH to a server, you must accept its host key. Do this for each node:

```bash
# Replace with your actual IPs from config.env
ssh root@10.11.11.12 "echo 'Host key accepted for N2'"
ssh root@10.11.11.13 "echo 'Host key accepted for N3'"
ssh root@10.11.11.14 "echo 'Host key accepted for N4'"
```

Type `yes` when prompted for each node.

### Step 3: Deploy Your Public Key

Copy your public key to each node's authorized_keys:

```bash
# Option A: Using ssh-copy-id (recommended)
ssh-copy-id -i ~/.ssh/id_ed25519 root@10.11.11.12
ssh-copy-id -i ~/.ssh/id_ed25519 root@10.11.11.13
ssh-copy-id -i ~/.ssh/id_ed25519 root@10.11.11.14

# Option B: Manual method
cat ~/.ssh/id_ed25519.pub | ssh root@10.11.11.12 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

### Step 4: Test Passwordless Access

```bash
# Should connect without prompting for password
ssh root@10.11.11.12 "hostname"
ssh root@10.11.11.13 "hostname"  
ssh root@10.11.11.14 "hostname"
```

Expected output:
```
n2
n3
n4
```

## SSH Config (Optional but Recommended)

Create `~/.ssh/config` for easier access:

```bash
cat >> ~/.ssh/config << 'EOF'

# Proxmox TB4 Cluster
Host n2
    HostName 10.11.11.12
    User root
    IdentityFile ~/.ssh/id_ed25519

Host n3
    HostName 10.11.11.13
    User root
    IdentityFile ~/.ssh/id_ed25519

Host n4
    HostName 10.11.11.14
    User root
    IdentityFile ~/.ssh/id_ed25519
EOF

chmod 600 ~/.ssh/config
```

Now you can simply run:
```bash
ssh n2
ssh n3
ssh n4
```

## Testing Loop Access

Verify you can reach all nodes with a loop:

```bash
for node in n2 n3 n4; do
    echo "=== Testing $node ==="
    ssh $node "hostname && uptime"
done
```

Expected output:
```
=== Testing n2 ===
n2
 10:30:45 up 5 days, ...
=== Testing n3 ===
n3
 10:30:46 up 5 days, ...
=== Testing n4 ===
n4
 10:30:47 up 5 days, ...
```

## Troubleshooting

### "Permission denied (publickey)"

Your key wasn't deployed correctly:
```bash
# Check if key exists on target
ssh -v root@10.11.11.12 2>&1 | grep "Offering public key"

# Re-deploy the key
ssh-copy-id -i ~/.ssh/id_ed25519 root@10.11.11.12
```

### "Connection refused"

SSH service not running or firewall blocking:
```bash
# Check SSH service (requires console access)
systemctl status ssh

# Check if port 22 is listening
ss -tlnp | grep :22
```

### "Host key verification failed"

Host key changed (maybe reinstalled Proxmox):
```bash
# Remove old host key
ssh-keygen -R 10.11.11.12

# Accept new key
ssh root@10.11.11.12
```

### "Too many authentication failures"

Too many keys tried before the right one:
```bash
# Specify the exact key to use
ssh -i ~/.ssh/id_ed25519 root@10.11.11.12

# Or limit keys in ssh config
# Add: IdentitiesOnly yes
```

## Security Notes

### For Homelab Use

This guide assumes a trusted homelab environment. In production:
- Use separate deploy keys
- Limit key permissions with `command=` in authorized_keys
- Consider bastion hosts

### Protect Your Private Key

```bash
# Ensure proper permissions
chmod 600 ~/.ssh/id_ed25519
chmod 700 ~/.ssh

# Never share your private key!
```

## Next Steps

1. [TB4 Foundation](03-tb4-foundation.md) - Set up kernel modules and hardware detection
