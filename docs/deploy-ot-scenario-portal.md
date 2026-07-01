# CyberRangeCZ Portal: Deploying the OT Sandbox Step-by-Step

This guide walks you through the step-by-step process of using the **CyberRangeCZ Web Portal** to import, allocate, and run the OT exploit-and-sabotage training scenarios. It applies to both:

- **Simple OT Sandbox** (`simple-ot-sandbox`) — 3-level foundational scenario
- **Complex OT Sandbox** (`complex-operator-ot-sandbox`) — 6-level advanced EWS pivot scenario

---

## Prerequisites: Access the Portal

Before starting, obtain the cluster IP of your running CyberRange:
1. From your host shell, print the cluster IP:
   ```bash
   vagrant ssh -c "sudo tofu -chdir=/root/devops-tf-deployment/tf-openstack-base output -raw cluster_ip"
   ```
2. Open your web browser and navigate to:
   ```text
   https://<YOUR_CLUSTER_IP>/
   ```
   *(Accept the self-signed SSL certificate warning if prompted).*
3. Log in with the default admin credentials:
   * **Username:** `crczp-admin`
   * **Password:** `password`

---

## Step 1: Import the Sandbox Definition

A **Sandbox Definition** dictates the network layout and VM software provisioning (Node-RED, OpenPLC, router firewall policies). To import it:

1. In the left sidebar of the portal, navigate to **Sandboxes** > **Definitions**.
2. Click the **Create** button in the top-right corner.
3. Fill in the form:
   * **Git URL:** Enter the Git repository URL containing your sandbox definition (e.g., `https://github.com/<org>/simple-ot-sandbox.git`). See the [OT Sandbox Deployment Guide](./deploy-ot-sandbox.md) for the expected repository structure.
   * **Revision:** Enter `main` (or a specific commit hash/branch name).
4. Click **Save**.
5. Once imported, the portal will automatically validate the YAML syntax. Click on the definition name to view the visual graph representation of your networks (`mgmt-net`, `ot-net`) and hosts (`attacker-host`, `scada-hmi`, `openplc-node`, `ot-router`).

---

## Step 2: Import the Training Definition

The training definition (stored in `training.json` in the same repository) defines the interactive levels, flags, hints, and scoring for the scenario:

1. In the left sidebar, navigate to **Trainings** > **Definitions**.
2. Click the **Create** button.
3. Fill in the form:
   * **Git URL:** Same URL as the sandbox definition above.
   * **Revision:** `main`
4. Click **Save**.
5. The portal will parse `training.json` and display the training title:
   - Simple sandbox: **"Operation Flow: Simple OT Hijack and Sabotage"**
   - Complex sandbox: **"Operation Waterborne: Industrial Control Hijack and Pivoting"**

---

## Step 3: Create and Allocate the Sandbox Pool

The **Sandbox Pool** is the actual set of VMs spawned inside OpenStack. To instantiate the pool:

1. In the left sidebar, navigate to **Sandboxes** > **Pools**.
2. Click the **Create Pool** button in the top-right corner.
3. Fill in the allocation details:
   * **Name:** Give your pool a recognizable name (e.g., `OT-Exploit-Lab-Pool`).
   * **Sandbox Definition:** Select the `simple-ot-sandbox` definition you imported in Step 1.
   * **Size:** Enter the number of isolated sandboxes to build (e.g., `1` for self-testing, or more for a student training session).
4. Click **Save**.
5. Click **Allocate** on the newly created pool.
   * **What happens now:** The platform calls OpenTofu/Terraform internally to build the OpenStack networks, router, and VMs. It then runs the Ansible playbook to install firewall rules on the router, Node-RED on the SCADA HMI, and OpenPLC on the PLC node.
   * *Status Indicator:* The pool status will transition from `Allocating` to `Active` (this takes about 5–10 minutes depending on internet speeds).

---

## Step 4: Create and Start a Training Run

Once the pool is **Active**, create a training instance to run the interactive scenario:

1. In the left sidebar, navigate to **Trainings** > **Instances**.
2. Click **Create**.
3. Fill in the form:
    * **Training Definition:** Select the appropriate training definition (e.g. **"Operation Flow: Simple OT Hijack and Sabotage"** or **"Operation Waterborne: Industrial Control Hijack and Pivoting"**).
    * **Sandbox Pool:** Select the pool you allocated in Step 3.
4. Click **Save**.
5. Go to the **Runs** tab of your training instance.
6. Click **Create Run** and assign participants.
7. Access the training stepper to begin the scenario.

---

## Step 5: Accessing the OT Virtual Machines

Once the training run is active, you can interact with the virtual machines:

1. Open the **Topology Map** from the training stepper interface.
2. **Accessing Consoles (Guacamole):**
   * Click on any host (e.g., `attacker-host`).
   * Click the **Web Console** link.
   * A new browser tab will open using the integrated Apache Guacamole client, giving you full interactive remote control over the virtual machine directly within your browser window.

> [!IMPORTANT]
> **Always use the Guacamole Web Console for trainee sessions.** The command tracking pipeline (Assessment, Command Timeline, Command Analysis tabs) only captures commands typed inside the Guacamole terminal. Direct SSH access bypasses all logging. See [command-tracking-and-assessment.md](./command-tracking-and-assessment.md) for full details.

3. Key services accessible from within the sandbox:

   **Simple OT Sandbox:**
   * **Node-RED Flow Editor (HMI):** `http://10.10.10.10:1880/` (from the attacker host)
   * **OpenPLC Admin Panel:** `http://192.168.99.10:8080/` (from the SCADA HMI only — blocked from the attacker by the router firewall)
     * Default credentials: `openplc` / `openplc`

   **Complex OT Sandbox:**
   * **Node-RED Flow Editor (HMI):** `http://192.168.100.10:1880/` (from the attacker host — `attacker-host` on `10.10.10.50`)
   * **Engineering Workstation (EWS):** `192.168.20.20` — accessible via SSH pivot from the SCADA HMI only
   * **OpenPLC (PLC):** `192.168.20.10` — Modbus port 502, accessible from the EWS only

---

## Step 6: Sandbox Reusability & Pool Recycling (The "Dirty Sandbox" Constraint)

When provisioning sandboxes for training runs, keep in mind the following platform allocation and state persistence limitations:

### 1. The "One-Trainee-Per-Sandbox" Limitation
* **Single Assignment:** A sandbox instance can only be allocated to **one active training run / participant** at a time.
* **Pool Exhaustion:** If your pool size is `1` and a trainee starts their run, the pool is fully claimed. No other students can start their training runs until more sandboxes are allocated or the pool is resized.

### 2. The "Dirty Sandbox" State Drift
* **State Persistence:** Once a trainee interacts with the sandbox (e.g. installs files, upgrades shells, edits Node-RED flows, writes to PLC registers), these changes are saved persistently to the VM disk volumes. 
* **Lack of Auto-Reset:** The platform does **not** roll back the guest VM disk states between runs. Reassigning the same sandbox to a new trainee will inherit the "dirty" state (pre-completed tasks, pre-configured exploits, already-harvested flags), rendering the exercise useless for the next run.

### 3. How to Clean Up and Reset the Sandbox
To recycle a pool and restore the sandbox to a completely clean state for the next run, you must destroy and recreate the instances:

1.  **Delete Active Training Instances:** 
   Navigate to **Trainings** > **Instances**, select the active instance, and delete it.
2.  **Re-allocate/Rebuild the Pool:**
   Navigate to **Sandboxes** > **Pools**, select your pool, and click **Delete** (or **Force Delete**). This executes Terraform destroy scripts to remove all dirty VMs and subnets inside OpenStack and immediately frees up host CPU/RAM resources.
3.  **Trigger Re-allocation:**
   Once deleted, click **Allocate** on the pool. This deploys a fresh set of VMs and executes the Ansible playbooks, guaranteeing a clean starting state.

---

## Sandbox Pool Resource Calculations & Hardware Constraints

Deploying the **Complex OT Sandbox** (`complex-operator-ot-sandbox`) reserves substantial CPU, RAM, and Disk resources from the OpenStack hypervisor.

### 1. Resource Allocations Per Sandbox Instance

Each sandbox in the pool spawns **5 virtual machines** with the following hardware profiles (defined by OpenStack flavors):

| Host / Role | Flavor | VCPUs | RAM (MB) | Disk (GB) |
|---|---|---|---|---|
| **attacker-host** (Kali Linux) | `kali` | 4 | 4,196 | 60 |
| **scada-hmi** (Node-RED HMI) | `standard.small` | 1 | 2,048 | 10 |
| **engineering-station** (EWS) | `standard.small` | 1 | 2,048 | 10 |
| **openplc-node** (OpenPLC PLC) | `standard.small` | 1 | 2,048 | 10 |
| **ot-gateway** (Gateway Router) | `standard.small` | 1 | 2,048 | 10 |
| **Total (per sandbox)** | | **8** | **12,388 (~12.1 GB)** | **100 GB** |

### 2. Resource Requirements for Additional Sandboxes
Because each sandbox in the pool is a completely isolated environment, every additional sandbox you allocate duplicates these requirements:

$$\text{Total Pool Reservation} = \text{Pool Size} \times \text{Single Sandbox Resources}$$

For example:
*   **Pool Size = 1 (Current Default):** Requires **8 VCPUs**, **~12.1 GB RAM**, and **100 GB Disk**.
*   **Pool Size = 2 (One additional sandbox):** Requires **16 VCPUs**, **~24.2 GB RAM**, and **200 GB Disk**.
*   **Pool Size = 5 (Small classroom):** Requires **40 VCPUs**, **~60.5 GB RAM**, and **500 GB Disk**.

> [!WARNING]
> **OpenStack Instance ERROR State:** If your hypervisor host runs out of physical RAM, the OpenStack Nova scheduler will experience memory starvation. When allocating or scaling up a pool, newly spawned instances will fail to boot and enter the `ERROR` state with a generic `unexpected state 'ERROR', wanted target 'ACTIVE'` message.
> 
> Always delete any old sandbox pools inside the portal before attempting to allocate a new pool on constrained hardware (< 64 GB RAM).

---

## Related Documentation

- [OT Sandbox Deployment Guide](./deploy-ot-sandbox.md) — Repository structure, topology, and Ansible role reference
- [Simple OT Sandbox Solutions](./ot-sandbox-solutions.md) — Complete training solution walkthrough (simple scenario)
- [Complex OT Sandbox Solutions](./complex-ot-solutions.md) — Complete training solution walkthrough (complex EWS pivot scenario)
- [Command Tracking & Assessment](./command-tracking-and-assessment.md) — How assessment tabs work and their limitations
- [Troubleshooting Commands](./troubleshooting-commands.md) — CLI reference for debugging
