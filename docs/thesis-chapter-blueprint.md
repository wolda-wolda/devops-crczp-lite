# BSc Thesis: 15-Page Technical Chapters Blueprint
*Structuring Chapters 3, 4, and 5 around the Simple & Complex OT Sandboxes on CyberRangeCZ*

This document provides a page-by-page layout blueprint to expand your technical implementation, empirical measurements, and platform observations into **15 pages of academic text** for your BSc thesis. 

---

## 📊 Chapter 3: System Design & Provisioning (5–6 Pages)
*Objective: Answer **RQ 1** by explaining how the Purdue Model was mapped to virtual topologies using OpenStack and Ansible.*

### Page 1: Purdue Model Mapping & Virtual Subnets
* **Academic Focus:** Explain the standard Purdue Model for Industrial Control Systems (ICS) security. Discuss how physical levels are logically mapped to virtual zones inside CyberRangeCZ.
* **Simple Sandbox:** Level 3 (Corporate/Attacker) `mgmt-net` (`10.10.10.0/24`) and Level 1/2 (Control/PLC) `ot-net` (`192.168.99.0/24`).
* **Complex Sandbox:** Corporate network (`10.10.10.0/24`), Operations/SCADA network (`192.168.100.0/24`), and Control network (`192.168.20.0/24`).
* **Visual:** Block diagram illustrating the subnet ranges, gateway interfaces, and demarcation points for both topologies.

### Page 2: Declarative Topologies (IaC) vs. Physical Testbeds
* **Academic Focus:** Evaluate the flexibility, scalability, and ease of reset of cloud-based sandboxes against physical PLC/SCADA racks. Explain the schema of the native `topology.yml` file.
* **Code Figure:** Include an excerpt of the network, VM nodes, and router interfaces declared in `topology.yml`.

### Page 3: Gateway Firewalls and Zone Isolation
* **Academic Focus:** Analyze why standard L3 routing (default Neutron behavior) must be restricted. Detail how the Ansible `router` role injects iptables forward rules to isolate zones.
* **Comparative Evidence:** Show the difference between the simple rules (blocking ports 502/8080) and the complex zoning rules (forcing all PLC traffic through EWS, blocking direct SCADA-to-PLC commands).
* **Code Figure:** Include the complete iptables forwarding chains from `router_forward_rules.txt` for both sandboxes.

### Page 4: SCADA HMI Service Provisioning
* **Academic Focus:** Document the deployment of Node-RED as a SCADA HMI. Discuss configuration security (running systemd services under the `root` account vs a restricted user).
* **Technical Detail:** Explain the necessity of programmatic interface overriding inside `settings.js` (`uiHost: "0.0.0.0"`) to make the interface reachable across subnets.

### Page 5: PLC Service Emulation & DB Automation
* **Academic Focus:** Discuss the compilation of OpenPLC V3 on Debian 12. Explain how physical I/O pins are virtualized into soft holding registers (Modbus addresses 40001+).
* **Provisioning Detail:** Detail the automated boot-time SQLite command used to configure the PLC directly into Run Mode to activate the Modbus listener without user intervention:
  ```sql
  sqlite3 /opt/OpenPLC_v3/webserver/openplc.db "UPDATE settings SET value = 'true' WHERE key = 'Start_run_mode';"
  ```

### Page 6: Engineering Workstation (EWS) Sidecar Provisioning
* **Academic Focus:** (Complex Sandbox only) Document the provisioning of the EWS node. Explain the role of the EWS as the central administrative pivot node in OT environments.
* **Telemetry Detail:** Describe the setup of the python safety monitor (`safety_monitor.py`) running as a systemd service to continuously poll holding register 0 and write results to `/var/log/safety_override.txt`.

---

## 💻 Chapter 4: Attack Proof-of-Concept & Execution (4–5 Pages)
*Objective: Explain the offensive methodology, lateral movement pivoting, and raw industrial packet injection.*

### Page 7: SCADA Entry & HMI Compromise (Florida Oldsmar Hack)
* **Academic Focus:** Map Level 2 to the Florida Oldsmar incident. Dissect the vulnerability of exposing unauthenticated graphical processes (Node-RED flow panels) on operations networks.
* **Technical Detail:** Explain the creation of the reverse shell flow using the Node-RED `exec` node to connect back to the Kali listener.

### Page 8: The "Dumb" Shell Pivot Hurdle (TTY Upgrade)
* **Academic Focus:** Document the execution constraints of standard shell payloads. Explain why a raw netcat reverse shell cannot prompt for credentials during SSH pivot operations.
* **Resolution:** Detail the three-step TTY upgrade mechanism using Python's pseudo-terminal module:
  ```python
  python3 -c 'import pty; pty.spawn("/bin/bash")'
  ```
* **Significance:** Relate this to standard red-team OSCP methodologies and its integration as a training learning objective.

### Page 9: Lateral Movement and EWS SSH Pivot (Ukraine Power Grid)
* **Academic Focus:** Map Level 3 to the Ukraine Power Grid incident. Discuss credential hygiene (plaintext files found on the SCADA server) and lateral movement through internal firewalls via standard protocols (SSH).
* **Technical Detail:** Walkthrough the SSH pivot into EWS (`operator` / `operator123`) and the subnet enumeration using port scans (`nmap -p 502 --open 192.168.20.0/24`) and passive sniffing (`tcpdump -i eth0 -n port 502`).

### Page 10: Modbus TCP Protocol Injection & Dissection
* **Academic Focus:** Detail how raw fieldbus commands exploit the lack of authentication in legacy OT protocols. 
* **The Sabotage Payload:** Dissect the exact 12-byte payload used to disable the pump: `\x00\x01\x00\x00\x00\x06\x01\x06\x00\x00\x27\x0f`.
* **Dissection Table:** Format a byte table outlining Transaction ID, Protocol ID, Length, Unit ID, Function Code (0x06 - Write Single Register), Reference Address, and Register Value.

### Page 11: Network Capture (PCAP) Audit & Logic Verification
* **Academic Focus:** Analyze the captured network trace (`modbus_sabotage_complex.pcap`). Trace the TCP handshake, write command sequence, Modbus acknowledgment response, and TCP session teardown.
* **Logic Validation:** Describe how the EWS safety monitor detects the register change and writes the validation flag to EWS log files, bypassing unrealistic PLC shell access.

---

## ⚙️ Chapter 5: Technical Challenges & Sizing Constraints (4–5 Pages)
*Objective: Answer **RQ 2** and **RQ 3** by analyzing platform bugs, hardware overheads, and real-time constraints.*

### Page 12: IaC and Dependency Challenges (Friction Points 1–3)
* **Challenge 1 (PEP 668):** Debian 12 externally-managed environment restrictions halting Ansible pip tasks.
* **Challenge 2 (Pymodbus 3):** Breaking change in the `read_holding_registers` positional-argument signature.
* **Challenge 3 (OpenPLC Build):** Non-idempotent compilation guards due to pre-existing database files.

### Page 13: CyberRangeCZ Platform Limitations (Friction Points 4–6)
* **Challenge 4 (Subnet Overlap Collision):** Sandbox IP blocks colliding with `192.168.128.0/17` hypervisor DHCP management interfaces.
* **Challenge 5 (Visualizer Dual-Home Bug):** Visual graph rendering crushes caused by multi-homed VM configurations.
* **Challenge 6 (Memory Starvation):** OpenStack Nova OOM failures resulting in instances entering `ERROR` states with generic `%!s(<nil>)` codes.

### Page 14: Virtualization Sizing Profiles & Resource Overhead
* **Academic Focus:** Analyze nested KVM virtualization performance footprints (L0 Host → L1 VM → L2 Guests).
* **Comparative Sizing Table:** Compile host hardware profiles (Ryzen 9955HX, 46GB RAM) and compare idle footprints (OpenPLC compiled runtime: 111MB RSS vs Node-RED: 130MB RSS, disk: 1.5GB baseline vs Kali: 18.2GB).

### Page 15: OT Real-Time Scheduling Constraints & Emulation Limits
* **Academic Focus:** Contrast real PLC hardware RTOS determinism (< 1 ms cycles) against virtualized OpenPLC CFS scheduling (`SCHED_OTHER` Linux policies).
* **Discussion:** Explain why standard kernel jitter (10-100 ms) is acceptable for security training (validation of logical flow) but unacceptable for real physical loop simulations.

### Page 16: Future Work: Pure-Software Extensions (Feasibility)
* **Academic Focus:** Prove the architectural flexibility of CyberRangeCZ by outlining three guest-level expansions:
  1. **Kinetic loop simulation:** Adding state variables (temperature calculations) to the EWS python daemon to simulate physical feedback loops.
  2. **Intrusion Detection:** Configuring Snort/Zeek on the gateway VM to parse captured PCAPs.
  3. **Protocol Diversity:** Activating DNP3 and S7comm ports on OpenPLC to map more diverse attack scenarios.
