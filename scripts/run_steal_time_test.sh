#!/usr/bin/env bash
# run_steal_time_test.sh

PLC_IP="192.168.130.29"
NETNS="qdhcp-d4c57ca8-3144-4845-9084-beed09b1ea43"
KEY_FILE="/tmp/pool-59.key"

echo "=== 1. INSTALLING UTILITIES ON PLC ==="
sudo ip netns exec "$NETNS" ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" debian@"$PLC_IP" "sudo apt-get update && sudo apt-get install -y sysstat stress-ng"

echo "=== 2. RUNNING STRESS IN BACKGROUND AND MEASURING ==="
# Launch stress-ng in the background on the guest, and run mpstat in the foreground
sudo ip netns exec "$NETNS" ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" debian@"$PLC_IP" "
  nohup stress-ng --cpu 2 --timeout 30s >/dev/null 2>&1 &
  sleep 1
  mpstat 1 30
"
