# BSc Thesis: Operational Technology (OT) Security Sandbox Research Findings

This document summarizes the findings, system designs, technical hurdles, and limits of emulating industrial environments investigated while developing OT training scenarios in CyberRangeCZ.

---

## 🎯 1. Research Overview & Goal
*The goal is to evaluate the architectural flexibility, IaC capabilities, and hardware requirements of the IT-focused CyberRangeCZ platform when adapted for OT security training.*

### Core Findings:
*   **IaC Adaptability:** Yes, the declarative configuration files (`topology.yml`) and provisioning playbooks (Ansible) are highly flexible and capable of deploying emulated industrial topologies (SCADA HMIs and PLCs).
*   **Security Modeling:** IT network virtualization layers can successfully replicate industrial zones (Purdue Model Levels 1, 2, and 3) using virtual routers and custom `iptables` forwarding rules.
*   **Timing Limits:** Due to virtualization scheduling layers and non-real-time guest kernels, emulated PLCs suffer from scheduling jitter, making this setup excellent for cyber-security logic exercises but unsuitable for high-precision physical loop testing.

---

## 🌐 2. Purde Model Topology & Provisioning (RQ 1)
*How can realistic OT network topologies be effectively modeled and provisioned within CyberRangeCZ using native IaC?*

### Network Layout & Zones
Our implementation maps virtual networks directly to Purdue Model levels:
1.  **Purdue Level 3 (Operations/SCADA):** Deployed as `mgmt-net` (`10.10.10.0/24`) containing `attacker-host` (Kali Linux) and `scada-hmi` (Node-RED).
2.  **Purdue Level 2 (Engineering):** Deployed as `operations-net` (`192.168.100.0/24`) containing `engineering-station` (vulnerable API server).
3.  **Purdue Level 1 (Control/PLC):** Deployed as `control-net` (`192.168.200.0/24`) containing `openplc-node` (OpenPLC Modbus server).

### Declarative Provisioning Configuration
*   **Topologies:** The sandbox structure is declared in a single `topology.yml` matching network subnets and static IP maps to virtual ports inside OpenStack.
*   **Software Execution:** Once VM instances boot, Ansible playbooks configure the software environments.
*   **PLC Run Mode Automation:** OpenPLC stores state configurations inside an SQLite database (`openplc.db`). To automate compilation and ensure the Modbus TCP server (port 502) is active automatically on startup, we run an automated database command:
    ```sql
    sqlite3 /opt/OpenPLC_v3/webserver/openplc.db "UPDATE settings SET value = 'true' WHERE key = 'Start_run_mode';"
    ```

---

## ⚠️ 3. Technical Challenges & Provisioning Complexities (RQ 2)
*What are the technical challenges when implementing an OT-specific attack scenario using IaC?*

During the deployment lifecycle, we resolved four major configuration anomalies:

### A. Network Interface Bindings
Modern packages default to loopback (`127.0.0.1`) for security. In the HMI setup, Node-RED had to be pre-configured with a custom `settings.js` specifying the interface binding prior to service initialization:
```javascript
module.exports = {
    uiHost: "0.0.0.0"
};
```
Without this configuration, the flow editor remains unreachable over the virtual network.

### B. Dependency Deprecations
OpenPLC relies on synchronous Modbus connections (`pymodbus.client.sync`). However, package managers on newer OS images (like Debian 12) default to Pymodbus 3.x, where these classes are removed. We fixed this by pinning the version inside the Python virtual environment:
```bash
pip3 install "pymodbus<3.0.0"
```

### C. Playbook Idempotency Guards
When compiling third-party code, standard playbooks check for the presence of SQLite database files to determine if compilation is required. However, because the empty database is checked into the repository, Ansible would skip compilation, resulting in missing MatIEC compilers. We corrected the `creates` guard to check for the output execution script (`start_openplc.sh`) instead.

---

## ❌ 4. Evaluation of the "Shared SSH Key" Design Flaw

Standard training environments frequently authorize a single SSH private key across all nodes in a sandbox, allowing the student to verify their attack by SSHing to the PLC and reading a flag (e.g., `/root/flag2.txt`).

*   **The Problem:** In a real-world OT system, this is highly unrealistic. PLCs are embedded controllers that run proprietary RTOS, do not host SSH daemons, and never share OS credentials with SCADA networks.
*   **The Pivot Workaround:** To design a realistic scenario, we deployed the **`complex-ot-sandbox`** introducing a multi-hop pivoting chain using a dedicated **Engineering Workstation (EWS)** and exploiting default OpenPLC web admin credentials on port `8080` (without using SSH keys):
    1.  **SCADA RCE:** Compromise Node-RED on HMI (`scada-hmi`).
    2.  **EWS Pivot:** Exploit a command injection vulnerability in the EWS backup API on port `5000` to pivot to the control network.
    3.  **PLC logic Compromise:** Connect from the EWS to the PLC's OpenPLC admin page (`192.168.200.10:8080`). Log in with default credentials (`openplc`/`openplc`) and upload a custom Python submodule payload (PSM) that writes the flag file to the public directory:
        ```python
        import os
        os.system("cat /root/flag3.txt > /opt/OpenPLC_v3/webserver/st_files/flag.txt")
        ```
    4.  **Download Flag:** Retrieve the flag via HTTP (`http://192.168.200.10:8080/st_files/flag.txt`).

---

## ⚡ 5. Sizing & Real-Time Emulation Constraints (RQ 3)
*What hardware resources are required, and what are the limitations regarding OT real-time constraints?*

### A. Nested Virtualization Overhead
Running CyberRangeZ inside a parent Vagrant KVM VM creates a nested hypervisor stack:
`Host CPU ──► KVM VM (OpenStack) ──► Guest instances (k3s/Sandboxes)`
This increases CPU context-switching overhead and disk I/O latency, requiring virtualization tuning settings like `volume_cache: unsafe` and `cpu_mode: host-passthrough` to achieve acceptable compilation and execution speeds.

### B. VM Sizing Footprint
Spawning sandboxes for multiple students requires careful resource budgeting:
*   **Kali Linux (Attacker VM):** Required **18.2 GB** of disk space due to massive security suite overlays and desktop graphical components.
*   **Debian 12 Server (HMI/PLC/EWS/Router):** Required only **333.5 MB** of disk space. Utilizing lightweight, headless Linux images is vital to maintaining sandbox density on local hardware.

### C. Emulation Scheduling Jitter
Real-world PLCs operate on deterministic scan cycle schedules (typically < 10ms jitter). A virtual PLC (OpenPLC) running as a Python process on a Debian Linux guest VM shares CPU scheduling with other virtual nodes and the parent host. Timing jitter occurs under CPU stress, meaning this emulation is suitable for logic and vulnerability testing but unsuitable for high-precision physical loops.

---

## 📊 6. Modbus TCP Protocol Dissection
*Analysis of the Modbus payload used to trigger the simulation monitor: `\x00\x01\x00\x00\x00\x06\x01\x06\x00\x00\x27\x0f`.*

*   `00 01` — **Transaction ID:** Matches the query and response.
*   `00 00` — **Protocol ID:** `0` indicates Modbus TCP.
*   `00 06` — **Length:** 6 bytes follow.
*   `01` — **Unit ID:** Slave device address 1.
*   `06` — **Function Code:** `0x06` instructs the PLC to **Write Single Register**.
*   `00 00` — **Register Address:** Targets Holding Register 0.
*   `27 0F` — **Register Value:** Hex representation of decimal `9999` (pressure overload value).
