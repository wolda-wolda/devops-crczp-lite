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

### D. SSH Configuration and Key Management Hurdles
We identified three operational complexities relating to the platform's native SSH configuration downloads:
1.  **Identity File Path Mismatches:** The downloaded SSH `config` file references a key path located at `~/.ssh/` with a long unique pool identifier name. If the student does not rename their local `key` file to match this name or edit the `config` paths, SSH authentication fails.
2.  **VM User Account Access:** The downloaded configuration specifies `User user` for connections. However, the user account `user` is only created during the optional user-stage of pool provisioning. Early administrative access or manual scenario debugging requires connecting as the base VM user (`debian` or `ubuntu`) using the range's management key.
3.  **Dynamic IP Drift on Reallocation:** Every time a sandbox pool is re-allocated or updated, the internal router and gateway (e.g., `man`) IP addresses change. Stale config files will attempt to jump through old, inactive gateway IPs, causing SSH connections to hang indefinitely at the `Connecting to IP port 22` stage.

---

## ❌ 4. Evaluation of the "Shared SSH Key" Design Flaw

Standard training environments frequently deploy identical SSH private keys across all guest instances in a sandbox pool. This allows the student to easily pivot from a compromised SCADA HMI to the isolated PLC and read a filesystem flag (e.g., `/root/flag2.txt` or `/root/flag3.txt`) to complete the training level. 

However, in a real-world industrial security audit, this approach introduces a significant architectural anomaly.

### The Tension Between Training Gamification and Real-World Fidelity
This design compromise highlights a fundamental conflict between **gamified training requirements** (Capture the Flag scoring) and **real-world physical fidelity**:

1.  **Operating System Anomalies on PLCs:** Real-world programmable logic controllers (e.g., Siemens S7, Allen-Bradley ControlLogix) are dedicated embedded hardware devices running custom microkernels or proprietary real-time operating systems (RTOS) like VxWorks or QNX. They do not run standard Unix SSH servers (`sshd`), nor do they support multi-user shell execution (`/bin/bash`).
2.  **Lack of Shared Authentication Keys:** In real-world industrial architectures, SCADA HMI web servers and PLCs communicate strictly via fieldbus or industrial network protocols (such as Modbus TCP, DNP3, or Profinet) on specific application ports. They never share operating system credentials, SSH keys, or active filesystem interfaces.
3.  **Real-World Attack Validation:** During an actual industrial cyber-attack (e.g., Industroyer or Stuxnet), an attacker does not verify the success of their process manipulation by SSHing into a PLC to read a text file. Instead, they check their success by:
    *   **Modbus Telemetry Feedback:** Querying the register values back via Modbus TCP (Function Code 3) to ensure the register retains the modified state.
    *   **SCADA Out-of-Band Verification:** Monitoring the SCADA visualization screen to see physical telemetry changes (e.g., water tank levels, motor speeds).
4.  **Operational Compromise of CTF Sandboxes:** To make the sandbox deployable and automatically gradable inside CyberRangeCZ, the designers chose to run OpenPLC as a service on a full Debian OS image and distribute the pool's SSH key to the node. While this is unrealistic, it is a compromise to allow the platform's automatic checker script to ssh in and verify progress.

### A Realistic, SSH-Free Compromise (The Complex EWS Pivot Scenario)
To resolve this design flaw and create a highly realistic training scenario, we developed the **`complex-ot-sandbox`** variant. This architecture removes all shared SSH keys between the nodes and models a realistic pivot exploit chain:

*   **Purdue Network Segmentation:** We separated the SCADA network from the PLC control network using a gateway firewall. The SCADA host (`scada-hmi`) is blocked from the PLC's SSH (22) and Web Admin (8080) ports and is restricted to Modbus TCP (502).
*   **The Engineering Workstation (EWS) Pivot:** We introduced the EWS node (`engineering-station`). In a real plant, EWS nodes are the only machines authorized to upload logic to PLCs. We simulated a vulnerable management API on the EWS on port `5000` (command injection) which the attacker exploits from the compromised SCADA host to gain a shell on the EWS.
*   **PLC Logic Exploitation via Default Credentials:** From the EWS, the attacker connects to the OpenPLC Web Admin Panel on port `8080` (which is allowed by the firewall). The attacker logs in using default credentials (`openplc`/`openplc`) and exploits OpenPLC's custom **Python SubModule (PSM)** hardware layer feature to upload a Python payload:
    ```python
    import os
    os.system("cat /root/flag3.txt > /opt/OpenPLC_v3/webserver/st_files/flag.txt")
    ```
*   **Web-Based Flag Extraction:** Once OpenPLC compiles the program, it executes the PSM script as root, copying the flag into the public web server directory. The attacker retrieves the flag using a standard HTTP request to `http://192.168.200.10:8080/st_files/flag.txt`, completing the level without utilizing any unrealistic operating system SSH keys.

### The Topology Visualization Bug's Accidental Realism Catalyst
During scenario validation, we discovered that if any host VM is configured as **dual-homed** (i.e. connected to two subnets simultaneously, such as HMI bridging operations and management subnets), the CyberRangeCZ topology visualizer fails to render the network graph, displaying a completely blank canvas in the student web portal.

While this represents a minor usability defect in the platform's visualizer library, **its impact on scenario realism is highly positive**:
1.  **Elimination of Vulnerable Designs:** Dual-homing hosts across security levels violates industrial standards (e.g. IEC 62443) because a compromise of the dual-homed host completely bypasses zone firewalls. 
2.  **Enforcement of Proper Routing:** To resolve the rendering bug, we single-homed all VMs and routed cross-subnet traffic strictly through the `ot-router` firewall. This configuration mirrors real-world industrial security practices, where zone firewalls inspect all SCADA-to-PLC protocol transactions.
3.  **Overall Platform Experience:** While the bug increases development overhead for content creators (who must write complex iptables forwarding policies on the router rather than simply dual-homing hosts), it ensures that students interact with secure, realistically-architected network topologies.

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

### D. Hypervisor Memory Starvation & OpenStack Instance ERROR State
During deployment scaling, we identified a critical operational resource constraint in nested environments:
*   **The Bottleneck:** While disk space is easily managed using base image shrinking, hypervisor physical memory (RAM) acts as the hard limit for sandbox density. Sizing allocations for a single pool (including Kali and server VMs) require over 18GB of active memory reservation.
*   **The Failure Mode:** When attempting to allocate a new sandbox pool (e.g., `complex-ot-sandbox`) while a previous pool remains active, the OpenStack Nova scheduler experiences memory starvation (OOM). 
*   **The Error Symptom:** OpenTofu/Terraform deployment outputs show newly spawned nodes entering the `ERROR` state instead of `ACTIVE` (`unexpected state 'ERROR', wanted target 'ACTIVE'`), with a generic empty error string (`last error: %!s(<nil>)`).
*   **Operational Mitigation:** Content creators and instructors must strictly enforce single-active-pool constraints on lower-spec hypervisors (e.g., < 64GB RAM). Previous sandbox pools must be completely deleted/destroyed in the portal UI to release the hypervisor memory reservation before a new sandbox can be allocated.

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
