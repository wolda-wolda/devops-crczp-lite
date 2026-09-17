# Operation Blackout Zero - Demo & Presentation Cheat-Sheet

This document provides a concise reference guide for demonstrating and presenting the **Smart Grid Co-Simulation Cyber Range Package** (`Operation Blackout Zero`) built for **CyberRangeCZ (KYPO CRP)** on OpenStack.

---

## 🎯 1. Core Concept & High-Level Pitch

* **What it is**: A 100% software-emulated, production-ready Smart Grid Co-Simulation package running on OpenStack Heat inside CyberRangeCZ.
* **Core Innovation**: Bridges a **Level 0 physical power grid simulation** (GridLAB-D IEEE 13-node feeder model) with a **Level 1/2 real software PLC** (OpenPLC V3), **Level 3 SCADA monitoring** (Node-RED, InfluxDB, Grafana), and an **Industrial DMZ (IDMZ)** using a custom Python co-simulation bridge (`gridlabd_bridge.py`).
* **Taxonomy**: Classified under cyber range taxonomies (Davis et al.) as an **Emulation Cyber Range (Virtualization-Based)** running full Linux VM kernels (Kali Linux, Debian 12) rather than synthetic network simulators.
* **Live Telemetry Pipeline**: `gridlabd_bridge.py` → Modbus TCP → OpenPLC → InfluxDB → Grafana. Real-time voltage/frequency/breaker data flows every 1 second.

---

## 🟢 2. Positives & Architectural Strengths

* **Strict Purdue Model (PERA) & IEC 62443 Alignment**:
  * 4-tier network zone segregation (Enterprise → IDMZ → SCADA Control Room → Substation PLCs → Level 0 Physics Engine).
  * Direct corporate-to-PLC and corporate-to-physics traffic is strictly blocked at the `purdue-gateway` router via `iptables` rules.
* **100% Virtualized & Cost-Effective**:
  * Eliminates the need for expensive physical hardware testbeds, physical PLCs, or specialized hardware-in-the-loop (HIL) equipment.
* **Real-Time Physical Feedback Loop**:
  * Modbus TCP register injection (`write_coil(0, False)`) actively drives GridLAB-D power flow calculations in real time, collapsing voltage from `240.0 V` → `0.0 V` and grid frequency `60.0 Hz` → `0.0 Hz`.
  * Grafana dashboard shows the collapse in real time via InfluxDB time-series data.
* **Clean Educational & Pedagogical Design**:
  * Story-driven levels with penalty-weighted hint progression and clean separation between objective descriptions and reference solution code.

---

## 🔴 3. Negatives, Trade-Offs & Physical Limitations

* **Timing Jitter & Lack of Hard Real-Time Guarantees**:
  * Because OpenPLC and GridLAB-D run inside guest virtual machines on non-real-time Linux kernels, thread scheduling jitter occurs.
  * *Key Takeaway*: Ideal for cybersecurity logic, protocol manipulation, and multi-tier pivoting exercises, but **unsuitable for millisecond-level physical protection relay timing validation**.
* **Co-Simulation Initial State Race Conditions**:
  * OpenPLC ST logic evaluates on boot before external bridge scripts connect. Required two fixes: an explicit `INIT_DONE` first-scan-cycle block in the ST code, and a one-time `write_coil(0, True)` from the bridge on initial connection.
* **Hypervisor Memory Footprint**:
  * Running 8 VM nodes concurrently (Kali, Jump, Enterprise, SCADA, EWS, 2x PLCs, Physics Router) requires ~12–14 GB of active RAM reservation per active sandbox pool.

---

## ⚙️ 4. Key Platform Hurdles & Thesis Highlights (The "Gotchas")

* **Dual-Homed Visualizer Crash Bug (Thesis Challenge 7)**:
  * *Issue*: If any non-router VM node is given multiple network interfaces (`net_mappings`), the CyberRangeCZ web visualizer graph engine crashes and displays a **completely blank canvas**.
  * *Solution*: Re-architected all nodes (including `idmz-jump`) to be strictly single-homed, routing all inter-subnet traffic through `purdue-gateway`. *Accidental realism catalyst: matches IEC 62443 anti-dual-homing guidelines.*
* **OpenSSH `PasswordAuthentication` Drop-Ins**:
  * Debian 12 / cloud-init images set `PasswordAuthentication no` in `/etc/ssh/sshd_config.d/`. Playbooks must update both main `sshd_config` and `/etc/ssh/sshd_config.d/*.conf` for SSH password brute-forcing (Hydra) to work.
* **Ansible `command:` vs `shell:` Redirection**:
  * `command: iptables-save > /etc/iptables/rules.v4` fails with `Unknown arguments` because `command` bypasses shell evaluation. Must use `shell:` for stdout redirection (`>`).
* **Node-RED `flowFile` Default Behavior**:
  * Node-RED defaults to loading `flows_<hostname>.json` (e.g., `flows_scada-hmi.json`), not `flows.json`. Must set `flowFile: "flows.json"` in `settings.js` explicitly, or deploy the flow file under both names.
* **Node-RED Missing `modbus-client` Config Node**:
  * Node-RED `modbus-getter` nodes reference a server config node by ID. If the `modbus-client` config node is missing from `flows.json`, Node-RED crashes on deploy with `Unknown node type`, preventing port 1880 from opening.
* **OpenPLC Coil Memory Buffer Initialization**:
  * `VAR_OUTPUT CB_MAIN_CLOSED AT %QX0.0 : BOOL := TRUE;` only sets the initial value at compile time. At runtime, OpenPLC's C-generated Modbus buffer initializes coils to `0` (`False`). Fix: add an explicit `INIT_DONE` first-scan-cycle block in the ST logic.
* **iptables Missing Return Paths for Co-Simulation Telemetry**:
  * The physics engine (`10.0.4.0/24`) needs to POST telemetry to InfluxDB on `scada-hmi` (`10.0.2.0/24`). Without an explicit FORWARD rule for `10.0.4.0/24` → `10.0.2.0/24`, the `purdue-gateway` silently drops the InfluxDB HTTP requests.
* **pymodbus Version Fragmentation**:
  * Import path changed across versions: `pymodbus.client` (v3.x), `pymodbus.client.sync` (v2.x), `pymodbus.client.tcp` (older). All Python scripts use a try/except import chain to handle any version.

---

## 📜 5. Real-World Attack Storytelling (Presentation Narrative)

* **Phase 1 (IDMZ Infiltration)** → **Ukraine 2015 Attack (BlackEnergy 3 / Sandworm)**:
  * Threat actors breached corporate networks and brute-forced weak VPN / Jump Host credentials to pivot into the Industrial DMZ.
* **Phase 2 (SCADA Reconnaissance)** → **2015 SCADA HMI Takeover**:
  * Attackers established SSH tunnels to monitor SCADA Node-RED & Grafana screens, viewing grid operations before taking action.
* **Phase 3 (Substation Sabotage)** → **Industroyer / CrashOverride (2016) & Industroyer2 (2022)**:
  * Malware transmitted unauthenticated Modbus TCP / IEC protocol payloads directly to substation PLCs to trip main feeder circuit breakers, inducing physical blackouts affecting 225,000+ people.

### Real-World Impact of Tripping a Circuit Breaker
* **Immediate**: Entire distribution feeder loses power — homes, hospitals, traffic lights go dark.
* **Cascading**: Adjacent feeders absorb orphaned load; if near capacity, their breakers trip too (cf. 2003 Northeast Blackout, 55 million affected).
* **Physical Danger**: Re-closing a breaker into an active fault causes arc flash explosions (20,000°C+). Rapid cycling destroys breaker mechanisms.

---

## 💻 6. Quick Demo Walkthrough Checklist

1. **Show `topology.yml`**: Point out single-homed node structure and Purdue 4-tier network subnets.
2. **Phase 1 (Hydra)**: Show SSH password brute-forcing on `idmz-jump` (`10.0.50.50` → `operator123`).
3. **Phase 2 (Tunneling & SCADA)**:
   * SSH port forwarding: `ssh -L 1880:10.0.2.10:1880 -L 3000:10.0.2.10:3000 operator@10.0.50.50`
   * Open Node-RED: `http://localhost:1880` — show the Modbus polling flow canvas.
   * Retrieve Flag 2: Click **Info (i)** tab for flow description, or run `curl -s http://localhost:1880/flows | grep FLAG`, or use `exec` node with `cat /root/flag.txt`.
   * Open Grafana: `http://localhost:3000` — login `admin`/`admin` — show live voltage at 240.0 V.
4. **Phase 3 (Modbus Attack)**:
   * Open Modbus tunnel: `ssh -L 5020:10.0.3.10:502 operator@10.0.50.50`
   * Initial read: `python3 modbus_attack.py --target 127.0.0.1 --port 5020 --action read` → **240.0 V, Breaker Closed: True**.
   * Execute attack: `python3 modbus_attack.py --target 127.0.0.1 --port 5020 --action trip_breaker`.
   * Final read: **0.0 V, Breaker Closed: False** → Switch to Grafana to show real-time voltage collapse!
   * (Optional) Restore: `python3 modbus_attack.py --target 127.0.0.1 --port 5020 --action close_breaker` → voltage recovers to 240.0 V.
