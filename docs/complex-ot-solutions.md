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

### Steps:
1.  Change the Node-RED `exec` node command to establish an SSH shell or run remote commands, OR simply SSH from the Node-RED host shell. Since the firewall allows HMI -> EWS SSH, execute commands via Node-RED:
    ```bash
    sshpass -p 'operator123' ssh -o StrictHostKeyChecking=no operator@192.168.20.20 "nmap -sn 192.168.20.0/24"
    ```
    *Alternatively, deploy a reverse shell flow to Kali and SSH directly from Kali to EWS.*
2.  Identify the active PLC IP address: **`192.168.20.10`**.

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
