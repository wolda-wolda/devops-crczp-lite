# How to Deploy a Simple OT Sandbox in CyberRangeCZ / KYPO

The CyberRangeCZ platform (built on the open-source **KYPO Cyber Range Platform**) uses a declarative, Git-ops-based workflow to provision virtual environments (sandboxes).

For details on how to build and register the base OS images used in these sandboxes, see the [Base Boxes & Image Management Guide](./base-boxes-management.md).

To deploy the OT exploit-and-sabotage training scenario (attacker machine, SCADA HMI, software PLC, and a gateway router with firewall policies), follow this guide.

---

## 1. Directory Structure of a KYPO Sandbox Definition

A sandbox definition is a standalone Git repository containing three main items:

1. **`topology.yml`**: Outlines the networks, routers, virtual machines (hosts), and their connection interfaces.
2. **`provisioning/`**: Contains Ansible roles and a playbook that configures software inside the VMs once they boot.
3. **`training.json`** *(optional)*: Defines the interactive training levels, flags, hints, and scoring.

Your repository directory structure should look like this:

```text
simple-ot-sandbox/
├── topology.yml
├── training.json
└── provisioning/
    ├── playbook.yml
    └── roles/
        ├── router/
        │   └── tasks/
        │       └── main.yml
        ├── openplc/
        │   └── tasks/
        │       └── main.yml
        └── nodered/
            └── tasks/
                └── main.yml
```

---

## 2. Define the Topology (`topology.yml`)

The topology defines three host VMs, one router, and two networks:

* `mgmt-net` (`10.10.10.0/24`): Connects the attacker to the SCADA HMI and the router.
* `ot-net` (`192.168.99.0/24`): Connects the router to the PLC (isolated from the attacker).

```yaml
name: simple-ot-sandbox

hosts:
  # 1. Attacker workstation (runs Kali GUI)

  - name: attacker-host

    base_box:
      image: kali
      mgmt_user: debian
    flavor: standard.large

  # 2. SCADA/HMI server (runs Node-RED)

  - name: scada-hmi

    base_box:
      image: debian-12-x86_64
      mgmt_user: debian
    flavor: standard.small

  # 3. Software PLC (runs OpenPLC)

  - name: openplc-node

    base_box:
      image: debian-12-x86_64
      mgmt_user: debian
    flavor: standard.small

routers:

  - name: ot-router

    base_box:
      image: debian-12-x86_64
      mgmt_user: debian
    flavor: standard.small

networks:

  - name: mgmt-net

    cidr: 10.10.10.0/24

  - name: ot-net

    cidr: 192.168.99.0/24

net_mappings:

  - host: attacker-host

    network: mgmt-net
    ip: 10.10.10.50

  - host: scada-hmi

    network: mgmt-net
    ip: 10.10.10.10

  - host: openplc-node

    network: ot-net
    ip: 192.168.99.10

router_mappings:

  - router: ot-router

    network: mgmt-net
    ip: 10.10.10.1

  - router: ot-router

    network: ot-net
    ip: 192.168.99.1

groups: []
```

> [!NOTE]
> All hosts use `debian-12-x86_64` except the attacker, which uses the `kali` image. Both are pre-registered in OpenStack Glance by the platform deployment.

---

## 3. Define the Provisioning Playbook (`provisioning/playbook.yml`)

The playbook maps configuration roles to the VMs defined in the topology:

```yaml

- name: Configure the Gateway Router

  hosts: ot-router
  become: yes
  roles:

    - router

- name: Configure the Software PLC Node

  hosts: openplc-node
  become: yes
  roles:

    - openplc

- name: Configure the SCADA/HMI Node

  hosts: scada-hmi
  become: yes
  roles:

    - nodered

```

### Router Role (`roles/router/tasks/main.yml`)

Blocks the attacker host from directly accessing the PLC on Modbus and admin ports:

```yaml
---

- name: Drop direct Modbus TCP (502) forwarding from attacker to OpenPLC

  iptables:
    chain: FORWARD
    source: 10.10.10.50
    destination: 192.168.99.10
    protocol: tcp
    destination_port: "502"
    jump: DROP
    action: insert

- name: Drop direct Web Admin (8080) forwarding from attacker to OpenPLC

  iptables:
    chain: FORWARD
    source: 10.10.10.50
    destination: 192.168.99.10
    protocol: tcp
    destination_port: "8080"
    jump: DROP
    action: insert
```

### Node-RED Role (`roles/nodered/tasks/main.yml`)

Installs Node-RED v3.1.15 (compatible with Node.js 18 on Debian 12), configures it to listen on all interfaces, and deploys the SCADA flag:

```yaml
---

- name: Install Node.js and npm

  apt:
    name:

      - nodejs
      - npm

    state: present
    update_cache: yes

- name: Install Node-RED globally

  npm:
    name: node-red
    version: '3.1.15'
    global: yes
    state: present

- name: Ensure Node-RED user directory exists

  file:
    path: /root/.node-red
    state: directory
    mode: '0755'

- name: Configure Node-RED settings

  copy:
    dest: /root/.node-red/settings.js
    content: |
      module.exports = {
          uiHost: "0.0.0.0"
      };
    mode: '0644'

- name: Create systemd unit file for Node-RED

  copy:
    dest: /etc/systemd/system/nodered.service
    content: |
      [Unit]
      Description=Node-RED Graphical Flow-builder
      After=syslog.target network.target

      [Service]
      Type=simple
      User=root
      Group=root
      WorkingDirectory=/root
      ExecStart=/usr/bin/env node-red
      Restart=always

      [Install]
      WantedBy=multi-user.target

- name: Start and enable Node-RED service

  systemd:
    name: nodered
    daemon_reload: yes
    state: started
    enabled: yes

- name: Install Modbus node inside Node-RED user directory

  npm:
    name: node-red-contrib-modbus
    path: /root/.node-red
    state: present

- name: Create SCADA flag file

  copy:
    dest: /root/flag.txt
    content: |
      FLAG{SCADA_EXPLOITED_RCE}
    mode: '0600'
```

> [!WARNING]
> Node-RED must be pinned to version `3.1.15`. The latest Node-RED (v4+) requires Node.js v22+, which is not available in Debian 12's default repositories. Additionally, `uiHost` must be set to `"0.0.0.0"` before the first service start, or Node-RED will only bind to `127.0.0.1`.

### OpenPLC Role (`roles/openplc/tasks/main.yml`)

Installs OpenPLC v3, configures auto-start run mode, and deploys a simulation monitor daemon that triggers the sabotage flag:

```yaml
---

- name: Install dependencies for compiling OpenPLC

  apt:
    name:

      - git
      - autoconf
      - libtool
      - make
      - g++
      - sqlite3
      - libsqlite3-dev
      - python3-pip

    state: present
    update_cache: yes

- name: Clone OpenPLC V3 repository

  git:
    repo: '<https://github.com/thiagoralves/OpenPLC_v3.git'>
    dest: /opt/OpenPLC_v3
    version: master

- name: Run OpenPLC installer (non-interactive)

  shell: ./install.sh linux
  args:
    chdir: /opt/OpenPLC_v3
    creates: /opt/OpenPLC_v3/start_openplc.sh

- name: Build systemd service unit file for OpenPLC

  copy:
    dest: /etc/systemd/system/openplc.service
    content: |
      [Unit]
      Description=OpenPLC Service
      After=network.target

      [Service]
      Type=simple
      WorkingDirectory=/opt/OpenPLC_v3
      ExecStart=/opt/OpenPLC_v3/start_openplc.sh
      Restart=always

      [Install]
      WantedBy=multi-user.target

- name: Configure OpenPLC to start run mode automatically

  command: >
    sqlite3 /opt/OpenPLC_v3/webserver/openplc.db
    "UPDATE settings SET value = 'true' WHERE key = 'Start_run_mode';"

- name: Reload systemd, enable, and start OpenPLC

  systemd:
    name: openplc
    daemon_reload: yes
    state: restarted
    enabled: yes
```

> [!IMPORTANT]
> The `creates` guard must check for `start_openplc.sh` (not `openplc.db`), because the database file exists in the Git repository but is not sufficient evidence that the full compilation completed. The `ExecStart` must point to `start_openplc.sh`, which activates the Python virtual environment before launching the webserver. Setting `Start_run_mode` to `true` ensures the Modbus server (port 502) starts automatically on boot.

---

## 4. Push the Sandbox Definition to Git

KYPO fetches sandbox definitions directly from Git repositories.

4. Initialize a new Git repository:

   ```bash
   git init
   git add .
   git commit -m "feat: initial OT sandbox definition"
   ```

5. Push it to a repository service (e.g., GitHub) that your CyberRangeCZ portal can access:

```bash
   git remote add origin <your-git-repo-url>
   git push -u origin main
   ```

---

## 5. Import the Sandbox Definition into CyberRangeCZ

6. Log in to the **CyberRangeCZ / KYPO Portal Web UI** (default: `<https://<cluster_ip>/`,> credentials: `crczp-admin` / `password`).
7. From the sidebar menu, navigate to **Sandboxes** > **Definitions**.
8. Click the **Create** button.
9. Enter the details:
   * **Git URL:** `<https://github.com/<org>/simple-ot-sandbox.git`>
   * **Revision:** `main`
10. Click **Save**. The portal will parse the `topology.yml` and display a visual graph of your sandbox networks.

---

## 6. Import the Training Definition

If your repository contains a `training.json` file:

11. Navigate to **Trainings** > **Definitions**.
12. Click the **Create** button.
13. Enter the same Git URL and revision as the sandbox definition.
14. Click **Save**. The portal will parse `training.json` and load the interactive training levels.

---

## 7. Allocate the Sandbox Pool

To deploy the VMs inside OpenStack:

15. Navigate to **Sandboxes** > **Pools**.
16. Click **Create Pool**.
17. Provide a name (e.g., `OT-Exploit-Lab-Pool`) and select the imported sandbox definition.
18. Set the **Size** (e.g., `1` for self-testing).
19. Click **Create & Allocate**.

### What happens behind the scenes:

20. **Terraform Orchestrator:** KYPO generates and runs Terraform manifests to build the networks, router, security groups, and spawn the 4 VMs (attacker, SCADA HMI, PLC, router).
21. **Ansible Provisioning:** Once the VMs boot, KYPO runs `provisioning/playbook.yml` to configure the firewall, Node-RED, OpenPLC, and the simulation monitor daemon.

---

## 8. Accessing the OT Environment

22. Once the pool status changes to **Active**, go to **Pools** > select pool > **Sandboxes**.
23. Select an allocated sandbox.
24. Access the VM consoles via the integrated web-based Guacamole client:
   * **attacker-host** — Kali desktop for running reconnaissance and exploits
   * **scada-hmi** — Node-RED flow editor at `<http://10.10.10.10:1880/`>
   * **openplc-node** — OpenPLC admin panel at `<http://192.168.99.10:8080/`> (credentials: `openplc` / `openplc`)

---

## Related Documentation

* [OT Sandbox Portal Guide](./deploy-ot-scenario-portal.md) — Step-by-step portal UI walkthrough
* [OT Sandbox Solutions](./ot-sandbox-solutions.md) — Complete training solution walkthrough
* [Troubleshooting Commands](./troubleshooting-commands.md) — CLI reference for debugging
* [Base Boxes & Image Management Guide](./base-boxes-management.md) — Sourcing and uploading OS images
