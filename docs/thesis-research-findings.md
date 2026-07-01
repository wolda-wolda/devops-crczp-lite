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

## 📊 1.1 Cyber Range Taxonomy & Classification

Under standard cyber range taxonomies (e.g., Davis et al.), this platform is classified as an **Emulation Cyber Range (Virtualization-based)**.

### Taxonomy Matrix

| Category | Definition | Sandbox Alignment |
|---|---|---|
| **Simulation** | Software-only conceptual models of network components (e.g., ns-3) without real OS instances. | *No* — Guest instances run full OS kernels. |
| **Emulation** | Hypervisor-based (KVM) or containerized virtualization running **real operating systems** and **applications**. | **Yes** — Boots full virtual machines (Kali Linux, Debian 12) with custom service configurations. |
| **Hybrid** | Integrates virtualized components with physical production hardware in-the-loop. | *No* — Environment is fully self-contained inside the virtual host. |
| **Physical** | Pure physical hardware infrastructure. | *No* — Entirely software-virtualized. |

### Hybrid Reality of the OT Sandbox

While the cyber range framework utilizes **emulation** for the guest hosts and networks, the OT scenario employs a hybrid approach:
*   **Emulated IT Infrastructure:** Attacker workstation, engineering stations, firewall routers, and operations subnets run on full VM guest kernels.
*   **Simulated Physical Process:** The PLC is a virtual PLC (OpenPLC) running inside a standard Debian VM. The physical hardware control logic (e.g., cooling pumps, actuators) and their feedback values are simulated programmatically in software.

---

## 🌐 2. Purdue Model Topology & Provisioning (RQ 1)
*How can realistic OT network topologies be effectively modeled and provisioned within CyberRangeCZ using native IaC?*

### Network Layout & Zones
Our implementation maps virtual networks directly to Purdue Model levels:
1.  **Purdue Level 3 (Operations/SCADA):** Deployed as `mgmt-net` (`10.10.10.0/24`) containing `attacker-host` (Kali Linux) and `scada-hmi` (Node-RED).
2.  **Purdue Level 2 (Engineering):** Deployed as `operations-net` (`192.168.100.0/24`) containing `engineering-station` (vulnerable API server).
3.  **Purdue Level 1 (Control/PLC):** Deployed as `control-net` (`192.168.20.0/24`) containing `openplc-node` (OpenPLC Modbus server).

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

### E. Sandbox IP Range Collisions with Hypervisor Management Networks
During multi-subnet routing design, we identified a critical routing collision that occurs if sandbox subnets overlap with the parent hypervisor's management infrastructure:
*   **The Overlap:** The CyberRangeCZ deployment allocates a very large address block (**`192.168.128.0/17`**) for its out-of-band management and DHCP interfaces (`man-network`).
*   **The Conflict:** If you assign an overlapping subnet to a sandbox zone (such as using `192.168.200.0/24` for a control cell network), the host VMs prioritize the directly connected kernel route on the management interface (`ens3`) over the default gateway router (`ens4`). 
*   **The Failure:** Packets sent to target hosts are misrouted directly out of the management interface onto the OOB bridge (which lacks a handler for that IP), leading to 100% packet loss and connection timeouts.
*   **The Remediation:** To bypass this conflict, all custom sandbox subnets must be configured outside the `192.168.128.0/17` range (for example, using `192.168.20.0/24` for control cells and `192.168.100.0/24` for operations), which forces the VM network stacks to route traffic correctly through the default gateway router interfaces.

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
To resolve this design flaw and create a highly realistic training scenario, we developed the **`complex-operator-ot-sandbox`** variant. This architecture removes all shared SSH keys between the nodes and models a realistic pivot exploit chain mimicking historical breaches:

*   **Purdue Network Segmentation:** We segmented the network into Corporate (`10.10.10.0/24`), Operations (`192.168.100.0/24`), and Control (`192.168.20.0/24`) zones using a gateway firewall router (`ot-gateway`).
*   **SCADA HMI Compromise (Florida Oldsmar Hack):** The attacker compromises an exposed, unauthenticated Node-RED interface on the SCADA HMI (`192.168.100.10`). In addition to finding a local flag, the attacker discovers a plain-text credential backup file (`ews_credentials.txt`) stored by an operator on the SCADA host.
*   **EWS Lateral Pivot (Ukraine Power Grid):** Using the stolen credentials (`operator` / `operator123`), the attacker SSHs into the Engineering Workstation (`192.168.20.20`) and scans the control network to discover the PLC IP (`192.168.20.10`).
*   **Process Sabotage (Modbus Hijack):** From the EWS, the attacker uses the Modbus TCP client to directly write `0` to Holding Register 0 (Address 40001) on the PLC, shutting down a critical cooling pump. The EWS safety monitor captures this protocol change and writes `FLAG{PUMP_DISABLED_SUCCESS}` to `/var/log/safety_override.txt` to confirm the exploit without using any unrealistic operating system shell access on the PLC itself.

### Historical Context: Real-World OT Incident Mapping

To validate the educational fidelity of the `complex-operator-ot-sandbox`, we mapped its mechanics to actual historical control system breaches:

#### 1. Oldsmar, Florida Water Treatment Plant Breach (2021)
*   **What Happened:** In February 2021, an unauthorized operator remotely accessed the plant's SCADA HMI software. The intruder took control of the operator's mouse and attempted to alter the dosing levels of sodium hydroxide (lye) from 100 parts per million to a highly corrosive 11,100 ppm, targeting the safety of the water supply.
*   **The Vector:** The breach occurred due to an exposed, outdated TeamViewer remote-access utility configured with weak shared credentials and no multi-factor authentication, bypassing basic perimeter barriers.
*   **Sandbox Replication:** Mimicked in **Level 2 (SCADA HMI Compromise)**. The HMI (`scada-hmi`) exposes an unauthenticated Node-RED graphical flow builder on port `1880`. The attacker gains full process control simply by connecting to the exposed web portal, highlighting the vulnerability of exposed industrial control panels.

#### 2. Ukraine Power Grid Cyberattack (2015)
*   **What Happened:** In December 2015, attackers successfully disabled 30 electrical substations in Ukraine, causing a power outage for over 230,000 customers.
*   **The Vector:** The attackers gained entry via spear-phishing on corporate networks, stole remote VPN credentials, pivoted laterally to the Operations Technology (OT) network, and accessed Engineering Workstations (EWS) to send unauthorized command sequences directly to circuit breakers.
*   **Sandbox Replication:** Mimicked in **Level 3 (EWS Pivot)**. The attacker cannot reach the PLC directly due to firewall rules. Instead, they extract plaintext credentials left on the HMI by an operator (representing bad credential hygiene), SSH laterally into the Engineering Workstation (`engineering-station`), and scan the isolated control subnet to target the PLC.

#### 3. Industroyer / Stuxnet (Protocol Injection)
*   **What Happened:** State-sponsored malware targeted Siemens PLCs (Stuxnet, 2010) and electrical transmission protocols (Industroyer, 2016) by injecting raw industrial protocol packets (Modbus TCP, DNP3, IEC-104) directly over the local network to overwrite memory blocks and cycle hardware.
*   **The Vector:** The malware was dropped onto intermediate engineering nodes, which then acted as protocol gateways to send raw command packets to target controllers that lacked cryptographic authentication.
*   **Sandbox Replication:** Mimicked in **Level 4 (Modbus Hijack)**. Rather than relying on unrealistic operating system access (like SSH keys on the PLC), the attacker remains on the EWS and runs `modbus` client commands to write `0` to PLC Holding Register 0. This alters the PLC's running state directly via protocol manipulation.

#### Abstraction and Simplification for Training Fidelity
While the sandbox environment abstracts certain complex engineering steps to remain viable within a limited training time frame, the core threat concepts and boundary conditions remain structurally equivalent:
*   **Florida Oldsmar Hack:** Instead of complex screen-hijack utilities (TeamViewer), the sandbox abstracts remote control via an unauthenticated graphical Node-RED flow builder. The underlying vulnerability — unauthenticated graphical process control exposure — is identical.
*   **Ukraine Power Grid Attack:** Instead of multi-month reconnaissance, directory credential harvesting, and corporate VPN hijacking, the sandbox abstracts lateral entry via operator credential leakage (`ews_credentials.txt`) stored on the SCADA server. The pivoting path through firewalls to the EWS is identical.
*   **Industroyer & Stuxnet:** Instead of writing specialized compiled payload drivers targeting proprietary RTUs/PLCs, the sandbox abstracts industrial payload delivery using pre-installed Modbus CLI tools. The vulnerability exploited — the lack of authentication in legacy industrial control protocols (Modbus TCP port 502) — is identical.

#### Pedagogical Sizing: Cognitive Load and Foundational Bridging
To evaluate the learning efficacy of the simplified `simple-ot-sandbox` against the `complex-ot-sandbox`, we apply **Cognitive Load Theory (CLT)** to the target audience profiles (IT security students transitioning to OT):
1. **Extraneous Load Reduction:** A student entering OT training faces high intrinsic complexity (learning industrial register indices, MBAP headers, and protocol behaviors). The `simple-ot-sandbox` isolates these variables by using a flat, linear pivot path (Attacker -> HMI -> PLC). The student is not distracted by complex routing, SSH credentials, or pseudo-terminal (PTY) upgrades, allowing them to focus entirely on **what** a Modbus cleartext command injection is.
2. **Pedagogical Staging Framework:**
   * **Stage 1 (Simple Sandbox): Foundational Protocol Logic.** Focuses on baseline OT exposures: unauthenticated HMI consoles (Oldsmar reference), gateway routing boundaries, and the raw insecurity of cleartext Modbus TCP port 502 command execution.
   * **Stage 2 (Complex Sandbox): Adversarial Pivoting & Lateral Movement.** Expands the scenario to include EWS hosts, credential harvesting, interactive reverse shells (requiring PTY spawning), network sweeps, and passive OT sniffing.
3. **Outcome:** By separating the training into two distinct sandboxes, the range provides a progressive learning curve. Trainees build confidence in OT protocol manipulation before addressing the realistic network pivoting challenges modeled in historical APT campaigns (like Ukraine 2015).

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
*   **The Failure Mode:** When attempting to allocate a new sandbox pool (e.g., `complex-operator-ot-sandbox`) while a previous pool remains active, the OpenStack Nova scheduler experiences memory starvation (OOM). 
*   **The Error Symptom:** OpenTofu/Terraform deployment outputs show newly spawned nodes entering the `ERROR` state instead of `ACTIVE` (`unexpected state 'ERROR', wanted target 'ACTIVE'`), with a generic empty error string (`last error: %!s(<nil>)`).
*   **Operational Mitigation:** Content creators and instructors must strictly enforce single-active-pool constraints on lower-spec hypervisors (e.g., < 64GB RAM). Previous sandbox pools must be completely deleted/destroyed in the portal UI to release the hypervisor memory reservation before a new sandbox can be allocated.

### E. Linear vs. Adaptive Training Pathways
During scenario packaging, we evaluated the deployment of linear vs. adaptive training definitions:
* **The Definition & Structural Differences (Source: *Vykopal et al., 2020*):**
  * **Linear Training:** A traditional, sequential model where all trainees follow a rigid, pre-defined path of phases or levels (e.g. foothold -> lateral pivot -> protocol sabotage). Trainees must submit correct answer keys or flags to unlock subsequent phases, and all participants encounter identical challenges regardless of prior proficiency or progress speed.
  * **Adaptive Training:** A personalized model where the training scenario dynamically adapts to individual student actions, timing, and errors in real-time. If the system detects a student struggling (via hint requests, slow completion rates, or failed login attempts), it dynamically routes them to a simplified helper network zone or lowers task difficulty. Conversely, if a student excels, the system inserts additional hurdles (e.g. secondary firewalls or dynamic honeytokens) to sustain engagement.
* **The Constraint:** Implementing adaptive training pathways (branching states, performance-based paths, and hint-penalty loops) requires complex state-machine declarations inside CyberRangeCZ, which increases development overhead and risk of deployment failures in time-constrained settings.
* **The Strategy:** The current scenario implementation uses a robust **linear pathway** (`training.json`), ensuring consistent execution. However, the platform's native adaptive pathways represent a major feasibility extension.
* **Pedagogical Branching Design:** 
  1. *Remediation Path:* If a student struggles to exploit the unauthenticated Node-RED interface (Level 2) and requests multiple hint packages, the adaptive scheduler can branch them to an auxiliary container tutorial detailing child process shell command executions in Node.js.
  2. *Advanced Path:* If a student completes the EWS pivot (Level 3) rapidly without requesting any hints, the scheduler can dynamically skip basic Modbus register writing and branch them directly to an advanced Level 4 where they must analyze and inject Siemens S7comm protocol variations, increasing the training cognitive load dynamically.

> **Academic Reference Source:**
> *Vykopal, J., Seda, V., & Tovarnak, D. (2020). "Design and Evaluation of Adaptive Cybersecurity Training in Cyber Ranges." In Proceedings of the 51st ACM Technical Symposium on Computer Science Education (SIGCSE).*

### F. Future Work: Transitioning to a Hybrid Cyber Range (Hardware-in-the-Loop)

While the current sandbox relies on software-emulated controllers (e.g., OpenPLC inside Debian VMs), the architecture is extensible to a **Hybrid Cyber Range (Hardware-in-the-Loop)** model. This integration connects virtual nodes to real-world industrial control hardware (e.g., physical PLCs, actuators, smart switches, or inline security appliances). 

---

### 1. Technical Setup & Deployment Configurations

Depending on the deployment target (local bare-metal vs. public cloud), the integration requires distinct networking patterns:

#### A. Local Bare-Metal Hypervisor Model
This model maps virtual interfaces directly to local physical switch ports:
1.  **Physical Host Setup:** A physical Ethernet port on the hypervisor host (e.g., `eth3`) is physically wired to a managed switch port configured for industrial traffic.
2.  **OpenStack Neutron Configuration:** In Neutron's ML2 config (`/etc/kolla/neutron-server/ml2_conf.ini`), map the physical network bridge to the host interface:
    ```ini
    [ml2_type_flat]
    flat_networks = physnet1
    [ovs]
    bridge_mappings = physnet1:br-eth3
    ```
3.  **Sandbox Provisioning:** Create a **flat provider network** inside OpenStack. Sandbox instances (e.g., the virtual Engineering Workstation) attached to this network are placed directly onto the physical L2 switch, enabling seamless communication with physical PLCs.

#### B. Public Cloud Deployment Model (GCP/AWS)
Because cloud-deployed ranges do not have access to local hardware interfaces, integration must be established over the internet using tunneling:

##### 1. Site-to-Site L3 VPN (Routable Protocols)
For standard IP-routable protocols (like Modbus TCP or DNP3):
1.  **VPC / Gateway Setup:** The sandbox's virtual firewall router (`ot-gateway`) is configured with a VPN tunnel daemon (e.g., WireGuard or StrongSwan).
2.  **Lab Gateway:** A physical VPN gateway router (like a pfSense box or Cisco router) is placed at the edge of the physical OT lab.
3.  **Routing:** Configure routing rules on the virtual gateway to route the virtual subnet range to the VPN tunnel interface and vice-versa, allowing L3 communication between the cloud Attacker VM and the local PLC.

##### 2. L2-over-L3 Encapsulation Overlays (Non-Routable Protocols)
For industrial protocols that rely on Layer 2 broadcast/multicast (e.g. GOOSE or PROFINET discovery):
1.  **VXLAN Overlay Tunnel:** Configure a VXLAN interface on the virtual gateway (`ot-gateway` or a dedicated bridge VM):
    ```bash
    ip link add vxlan0 type vxlan id 42 group 239.1.1.1 dev eth0 dstport 4789
    ip link set vxlan0 up
    ```
2.  **Lab Endpoint:** A physical gateway PC or Raspberry Pi inside the physical lab is configured with a matching VXLAN endpoint and bridged directly to the physical OT network switch.
3.  **L2 Adjacency:** This encapsulates raw L2 frames into UDP packets, allowing them to traverse the internet tunnel and decapsulate directly onto the local lab network, making cloud VMs appear physically connected to the local switch.

---

### 2. Multi-Scenario Examples (Use Cases)

Below are three examples of how a hybrid attack path behaves and how the traffic flows:

```
┌──────────────────────────────────────┐
│  Cloud CyberRange (GCP/AWS)          │
│  [Attacker VM] ──► [ot-gateway]      │
└─────────────────────────┬────────────┘
                          │ (VPN / VXLAN Tunnel)
                          ▼
┌──────────────────────────────────────┐
│  Physical OT Hardware Lab            │
│  [Lab Gateway] ──► [Managed Switch]  │
│                           │          │
│      ┌────────────────────┼──────────┐
│      ▼                    ▼          ▼
│ [Siemens S7-1500]    [Relay IED]   [SCADA HMI]
└──────────────────────────────────────┘
```

#### Example A: Routable Modbus TCP Hijacking (Level 1/2)
*   **The Target:** A physical Modbus-enabled pump controller (PLC) regulating water tank pressure in the physical lab.
*   **The Attack Path:**
    1.  Trainee initiates a Modbus write command from the cloud-based `attacker-host`:
        ```bash
        modbus <physical-plc-ip> 0=9999
        ```
    2.  The packet is routed through `ot-gateway` and sent across the IPsec/WireGuard VPN tunnel.
    3.  The physical lab firewall decapsulates the packet and forwards it to the physical PLC.
    4.  The physical PLC processes the write request, bringing Holding Register 0 to `9999` (overpressure simulation), which opens a physical exhaust valve and illuminates a red indicator LED on the lab console.

#### Example B: Non-Routable L2 GOOSE Frame Injection
*   **The Target:** A physical Intelligent Electronic Device (IED / Protection Relay) controlling a physical circuit breaker in an electrical substation model.
*   **The Attack Path:**
    1.  Trainee generates a raw multicast IEC 61850 GOOSE payload on the cloud VM targeting the multicast MAC `01-0C-CD-01-00-01` to trigger a fake "Overcurrent Trip" signal.
    2.  Because the frame is non-routable, it is routed into the local VXLAN interface on `ot-gateway`.
    3.  The VXLAN interface wraps the Ethernet frame in a UDP wrapper and sends it across the internet to the local lab endpoint.
    4.  The local endpoint strips the UDP header and broadcasts the raw GOOSE frame onto the physical switch.
    5.  The physical Protection Relay processes the multicast frame, matches the dataset, and immediately opens the physical circuit breaker with an audible click.

#### Example C: Proprietary Siemens S7comm-plus Command Replay
*   **The Target:** A physical Siemens S7-1500 PLC regulating a conveyor belt assembly line.
*   **The Attack Path:**
    1.  Trainee captures legitimate S7comm-plus traffic from the physical network (e.g. via passive tcpdump or previous exercise captures).
    2.  From the cloud attack host, they run a replay script to inject a series of proprietary `CPU STOP` command packets targeting TCP port `102` of the Siemens PLC.
    3.  The packets travel via the Direct Port Mapping (local bare-metal setup) to ensure sub-millisecond delivery.
    4.  The physical PLC receives the replay sequence, halts CPU program execution, and stops the physical conveyor belt motor immediately.

---

### 3. Technical Limitations & Challenges

While powerful, implementing a hybrid cyber range introduces several system-level constraints:

#### A. Network Latency & Jitter
*   **The Constraint:** Cloud-to-lab tunnels suffer from network latency (typically > 20ms over WAN) and packet arrival jitter.
*   **The Impact:** High-precision industrial networks that rely on real-time protocols with strict determinism (such as PROFINET IRT or EtherCAT, requiring sub-millisecond sync cycles) cannot function properly over WAN tunnels. If the connection fails to meet timing windows, the PLC enters a watchdog timeout state and trips a hardware fault.
*   **Remediation:** High-precision loop simulations must be kept entirely local on bare-metal servers, reserving cloud tunnels for non-real-time L3 protocols like Modbus TCP, DNP3, and OPC-UA.

#### B. MTU Overhead & Fragmentation
*   **The Constraint:** Tunnel encapsulation (like VXLAN or GRE) adds byte overhead to the IP header (50 bytes for VXLAN).
*   **The Impact:** Standard Ethernet packets (1500 bytes MTU) will exceed the maximum transmission size and become fragmented when entering the tunnel. Because legacy PLC TCP/IP stacks often have primitive network drivers, they cannot handle fragmented IP packets and will drop them, causing connection drops or timeouts.
*   **Remediation:** Ensure path MTU discovery is active, and configure the cloud virtual interfaces to use a reduced MTU (e.g. `1450` for VXLAN or `1420` for WireGuard) to prevent fragmentation.

#### C. VLAN Tagging & Managed Switch Constraints
*   **The Constraint:** Using OpenStack's Neutron VLAN network provider mode requires mapping VLAN tags from the virtual environment straight onto physical switches.
*   **The Impact:** The physical lab switch ports must be configured as IEEE 802.1Q trunk ports with matching VLAN ID memberships. Stale configuration, spanning-tree blocking, or switchport security limits (like maximum MAC limits per port) will block the OpenStack virtual interfaces from communicating.

#### D. Hardware Safety & Mechanical Damage
*   **The Constraint:** Trainees are executing real exploits against physical machinery.
*   **The Impact:** Unlike virtual machines that can be rebooted or reset to snapshot, physical hardware can be permanently damaged by malicious control sequences (e.g. cycling a circuit breaker thousands of times, or running a motor past mechanical limits).
*   **Remediation:** Physical hardware setups must incorporate hard-wired safety interlocks (like limit switches and physical emergency stops) and software sanity bounds in the PLC program that override malicious write inputs to prevent equipment damage or operator injury.

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
