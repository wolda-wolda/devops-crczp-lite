# How to Deploy a Simple OT Sandbox in CyberRangeCZ / KYPO

The CyberRangeCZ platform (built on the open-source **KYPO Cyber Range Platform**) uses a declarative, Git-ops-based workflow to provision virtual environments (sandboxes). 

For details on how to build and register the base OS images used in these sandboxes, see the [Base Boxes & Image Management Guide](./base-boxes-management.md).

To deploy a simple OT environment (e.g., an attacker machine, a SCADA HMI web portal, and a virtual PLC node controlling a water pump), you must follow this 6-step process.

---

## 1. Directory Structure of a KYPO Sandbox Definition

A sandbox definition is a standalone Git repository containing two main items:
1. **`topology.yml`**: Outlines the networks, routers, virtual machines (hosts), and their connection interfaces.
2. **Ansible Roles & Playbooks**: Configures software (Node-RED, OpenPLC, scripts) inside the VMs once they boot.

Your repository directory structure should look like this:

```text
ot-sandbox-definition/
├── topology.yml
├── playbook.yml
└── roles/
    ├── openplc/
    │   └── tasks/
    │       └── main.yml
    └── nodered/
        └── tasks/
            └── main.yml
```

---

## 2. Step 1: Define the Topology (`topology.yml`)

Create `topology.yml` to set up the networking and virtual instances. We will create two networks:
* `mgmt-net`: Connects the Attacker VM to the SCADA HMI.
* `ot-net`: Connects the SCADA HMI to the PLC (isolated from the attacker).

```yaml
name: ot-sandbox-definition

hosts:
  # 1. Attacker workstation (Level 3)
  - name: attacker-host
    base_box:
      image: debian-12-x86_64
      mgmt_user: debian
    flavor: standard.small

  # 2. SCADA/HMI server (Level 2)
  - name: scada-hmi
    base_box:
      image: ubuntu-noble-x86_64
      mgmt_user: ubuntu
    flavor: standard.medium

  # 3. Software PLC (Level 1)
  - name: openplc-node
    base_box:
      image: ubuntu-noble-x86_64
      mgmt_user: ubuntu
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

  - host: scada-hmi
    network: ot-net
    ip: 192.168.99.5

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

groups:
  - name: ot-group
    nodes:
      - attacker-host
      - scada-hmi
      - openplc-node
      - ot-router
```


---

## 3. Step 2: Define the Provisioning Playbook (`playbook.yml`)

The `playbook.yml` maps configuration roles to the VMs defined in the topology.

```yaml
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

### Example PLC Role (`roles/openplc/tasks/main.yml`)
```yaml
---
- name: Install Git and dependencies
  apt:
    name:
      - git
      - autoconf
      - libtool
      - make
      - g++
      - sqlite3
      - libsqlite3-dev
    state: present
    update_cache: yes

- name: Clone OpenPLC V3
  git:
    repo: 'https://github.com/thiagoralves/OpenPLC_v3.git'
    dest: /opt/OpenPLC_v3

- name: Install OpenPLC (this can take a few minutes)
  shell: ./install.sh linux
  args:
    chdir: /opt/OpenPLC_v3

- name: Start OpenPLC background service
  systemd:
    name: openplc
    state: started
    enabled: yes
```

### Example Node-RED SCADA Role (`roles/nodered/tasks/main.yml`)
```yaml
---
- name: Install Node.js
  apt:
    name: nodejs
    state: present

- name: Install npm
  apt:
    name: npm
    state: present

- name: Install Node-RED globally
  npm:
    name: node-red
    global: yes
    state: present

- name: Install Modbus node for Node-RED dashboard
  npm:
    name: node-red-contrib-modbus
    path: /root/.node-red
    state: present

- name: Start Node-RED service
  shell: node-red-start &
```

---

## 4. Step 3: Push the Sandbox Definition to Git

KYPO fetches sandbox definitions directly from Git repositories.
1. Initialize a new Git repository:
   ```bash
   git init
   git add .
   git commit -m "feat: initial OT sandbox definition"
   ```
2. Push it to a repository service (e.g., GitLab or GitHub) that your CyberRangeCZ portal can access:
   ```bash
   git remote add origin <your-git-repo-url>
   git push -u origin main
   ```

---

## 5. Step 4: Import the Sandbox Definition into CyberRangeCZ

1. Log in to the **CyberRangeCZ / KYPO Portal Web UI**.
2. From the sidebar menu, navigate to **Sandboxes** > **Definitions**.
3. Click the **Create** button (often top-right).
4. Enter the details:
   * **Git URL:** `https://your-gitlab-server.com/group/ot-sandbox-definition.git`
   * **Revision:** `main` (or a specific commit hash)
5. Click **Save**. The portal will parse the `topology.yml` and display a visual graph of your sandbox networks.

---

## 6. Step 5: Allocate the Sandbox Pool

To actually deploy and instantiate the VMs inside OpenStack, you must allocate a Pool:
1. Navigate to **Sandboxes** > **Pools**.
2. Click **Create Pool**.
3. Provide a name (e.g., `OT_Training_Pool_1`) and select the imported **OT Sandbox Definition**.
4. Set the **Size** (e.g., `5` if you want to deploy 5 identical isolated copies of this OT environment for 5 students).
5. Click **Create & Allocate**.

### What happens behind the scenes:
1. **Terraform Orchestrator:** KYPO automatically generates and runs Terraform manifests targeting OpenStack to build the networks, router, security groups, and spawn the 3 VMs.
2. **Ansible Provisioning:** Once the VMs boot, KYPO runs the `playbook.yml` through an internal Ansible proxy, configuring Node-RED on `scada-hmi` and OpenPLC on `openplc-node`.

---

## 7. Step 6: Accessing the OT Environment

1. Once the pool status changes to **Active**, go to **Pools** > **OT_Training_Pool_1** > **Sandboxes**.
2. Select an allocated sandbox.
3. You can access the consoles of the VMs directly using the integrated web-based console client (Guacamole) in your browser:
   * Access the **SCADA-HMI** console to design the dashboard.
   * Access the **Attacker** console to test exploiting the Modbus protocol on the PLC at `192.168.99.10:502`.
