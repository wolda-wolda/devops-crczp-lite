#!/usr/bin/env bash
# collect_optimized_data.sh
# Automated dynamic data collector for optimized scenarios.
# Run inside the Vagrant VM as root.

BACKUP_DIR="/vagrant/optimized_data_dumps"
mkdir -p "$BACKUP_DIR"

source /etc/kolla/admin-openrc.sh
source /root/kolla-ansible-venv/bin/activate

echo "=== RESOLVING TOPOLOGY DYNAMICALLY ==="

# 1. Detect the active sandbox server prefix
PLC_SERVER=$(openstack server list --all -c Name -f value | grep "openplc-node" | head -n 1 | tr -d '\r')

if [ -z "$PLC_SERVER" ]; then
  echo "Error: No active openplc-node server found in OpenStack. Make sure a pool is allocated and active."
  exit 1
fi

# Example: default-p0000000057-s0000000060-openplc-node
# Extract prefix: default-p0000000057-s0000000060-
PREFIX=$(echo "$PLC_SERVER" | grep -o -E '^default-p[0-9]+-s[0-9]+-' | tr -d '\r')
echo "Detected Sandbox Prefix: $PREFIX"

# Extract Pool ID
POOL_ID_RAW=$(echo "$PREFIX" | grep -o -E 'p[0-9]+' | grep -o -E '[0-9]+' | tr -d '\r')
# Strip leading zeros for filename matching (e.g. pool-57.key)
POOL_ID=$((10#$POOL_ID_RAW))
echo "Detected Pool ID: $POOL_ID"

KEY_FILE="/tmp/pool-${POOL_ID}.key"
if [ ! -f "$KEY_FILE" ]; then
  # Fallback: search for any key file in /tmp/
  KEY_FILE=$(find /tmp/ -name "pool-${POOL_ID}.key" -o -name "pool-*${POOL_ID}*.key" | head -n 1 | tr -d '\r')
  if [ -z "$KEY_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Error: SSH private key file not found in /tmp/ for Pool $POOL_ID"
    exit 1
  fi
fi
echo "Using Key File: $KEY_FILE"

# Resolve network namespace
MAN_NET_NAME="${PREFIX}man-network"
NET_ID=$(openstack network show "$MAN_NET_NAME" -c id -f value | tr -d '\r')
if [ -z "$NET_ID" ]; then
  echo "Error: Management network $MAN_NET_NAME not found in OpenStack."
  exit 1
fi
NETNS="qdhcp-${NET_ID}"
echo "Using Network Namespace: $NETNS"

# Function to get management IP of a VM
get_mgmt_ip() {
  local vm_name="$1"
  local full_name="${PREFIX}${vm_name}"
  echo "Querying IP for VM: $full_name" >&2
  local ip=$(openstack server list --name "$full_name" -c Networks -f value | python3 -c "import sys, ast; data = ast.literal_eval(sys.stdin.read().strip()); print([v[0] for k, v in data.items() if 'man-network' in k][0])" 2>/dev/null)
  echo "Resolved IP: $ip" >&2
  echo "$ip"
}

PLC_IP=$(get_mgmt_ip "openplc-node")
HMI_IP=$(get_mgmt_ip "scada-hmi")
EWS_IP=$(get_mgmt_ip "engineering-station")
DMZ_IP=$(get_mgmt_ip "dmz-jump")
# Simple router is named 'ot-router', complex gateway is named 'ot-gateway'
ROUTER_IP=$(get_mgmt_ip "ot-gateway")
if [ -z "$ROUTER_IP" ]; then
  ROUTER_IP=$(get_mgmt_ip "ot-router")
  SCENARIO_TYPE="simple"
else
  SCENARIO_TYPE="complex"
fi

echo "=== SANDBOX RESOLVED ==="
echo "Scenario Type: $SCENARIO_TYPE"
echo "PLC IP: $PLC_IP"
echo "HMI IP: $HMI_IP"
[ -n "$EWS_IP" ] && echo "EWS IP: $EWS_IP"
[ -n "$DMZ_IP" ] && echo "DMZ IP: $DMZ_IP"
echo "Router IP: $ROUTER_IP"

ssh_cmd() {
  sudo ip netns exec "$NETNS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY_FILE" debian@"$1" "$2"
}

# 1. Hypervisor Host specs
echo "Collecting hypervisor host specs..."
lscpu > "$BACKUP_DIR/host_cpu.txt"
free -h > "$BACKUP_DIR/host_ram.txt"
df -h > "$BACKUP_DIR/host_disk.txt"
openstack server list --all > "$BACKUP_DIR/openstack_servers.txt"
openstack network list > "$BACKUP_DIR/openstack_networks.txt"
openstack flavor list > "$BACKUP_DIR/openstack_flavors.txt"

# 2. HMI specs
echo "Collecting HMI specs..."
ssh_cmd "$HMI_IP" "free -h" > "$BACKUP_DIR/hmi_ram.txt"
ssh_cmd "$HMI_IP" "df -h" > "$BACKUP_DIR/hmi_disk.txt"
ssh_cmd "$HMI_IP" "sudo ss -tlnp" > "$BACKUP_DIR/hmi_ports.txt"
ssh_cmd "$HMI_IP" "sudo systemctl status nodered" > "$BACKUP_DIR/hmi_nodered_status.txt"

# 3. PLC specs
echo "Collecting PLC specs..."
ssh_cmd "$PLC_IP" "free -h" > "$BACKUP_DIR/plc_ram.txt"
ssh_cmd "$PLC_IP" "df -h" > "$BACKUP_DIR/plc_disk.txt"
ssh_cmd "$PLC_IP" "sudo ss -tlnp" > "$BACKUP_DIR/plc_ports.txt"
ssh_cmd "$PLC_IP" "sudo systemctl status openplc" > "$BACKUP_DIR/plc_openplc_status.txt"

# 4. EWS & DMZ specs (if complex scenario)
if [ "$SCENARIO_TYPE" = "complex" ]; then
  echo "Collecting Complex-only specs..."
  ssh_cmd "$EWS_IP" "free -h" > "$BACKUP_DIR/ews_ram.txt"
  ssh_cmd "$EWS_IP" "df -h" > "$BACKUP_DIR/ews_disk.txt"
  ssh_cmd "$EWS_IP" "sudo systemctl status safety-monitor 2>/dev/null || sudo systemctl status simulation-monitor 2>/dev/null" > "$BACKUP_DIR/ews_status.txt"
  
  ssh_cmd "$DMZ_IP" "free -h" > "$BACKUP_DIR/dmz_ram.txt"
  ssh_cmd "$DMZ_IP" "df -h" > "$BACKUP_DIR/dmz_disk.txt"
fi

# 5. Router info
echo "Collecting Router info..."
ssh_cmd "$ROUTER_IP" "ip route" > "$BACKUP_DIR/router_routing.txt"

echo "=== DATA DUMP COMPLETED ==="
echo "All specs have been collected in $BACKUP_DIR"
