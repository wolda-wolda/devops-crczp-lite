# CyberRangeCZ Portal: Deploying the OT Sandbox Step-by-Step

This guide walks you through the step-by-step process of using the **CyberRangeCZ Web Portal** to import, allocate, and run the OT exploit-and-sabotage training scenario.

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
5. The portal will parse `training.json` and display the training title: **Simple OT Simulation Sandbox**.

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
   * **Training Definition:** Select **Simple OT Simulation Sandbox**.
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
3. Key services accessible from within the sandbox:
   * **Node-RED Flow Editor:** `http://10.10.10.10:1880/` (from the attacker host or SCADA HMI)
   * **OpenPLC Admin Panel:** `http://192.168.99.10:8080/` (from the SCADA HMI only — blocked from the attacker by the router firewall)
     * Default credentials: `openplc` / `openplc`

---

## Step 6: Clean Up / Deleting the Sandbox Pool

To free up CPU and RAM on your server when you are done:

1. Go to **Trainings** > **Instances** and delete any active training instances first.
2. Go to **Sandboxes** > **Pools**.
3. Select your pool and click **Delete**.
4. Confirm the deletion.
   * **What happens:** KYPO automatically runs Terraform destroy tasks in OpenStack to delete all VMs, floating IPs, and subnets. Your host resources will be immediately freed up.

---

## Related Documentation

- [OT Sandbox Deployment Guide](./deploy-ot-sandbox.md) — Repository structure, topology, and Ansible role reference
- [OT Sandbox Solutions](./ot-sandbox-solutions.md) — Complete training solution walkthrough
- [Troubleshooting Commands](./troubleshooting-commands.md) — CLI reference for debugging
