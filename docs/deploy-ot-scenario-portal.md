# CyberRangeCZ Portal: Deploying a Simple OT Sandbox Step-by-Step

This guide walks you through the step-by-step process of using the **CyberRangeCZ Web Portal** to import, allocate, and access a simple OT (SCADA HMI + OpenPLC) sandbox environment.

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

## Step 1: Import the Sandbox Definition into the Portal

A **Sandbox Definition** dictates the network layout and VM software provisioning (Node-RED + OpenPLC). To import it:

1. In the left sidebar of the portal, navigate to **Sandboxes** > **Definitions**.
2. Click the **Create** button in the top-right corner.
3. Fill in the form:
   * **Git URL:** Enter the public Git repository containing your sandbox definition (which houses your `topology.yml` and Ansible files, see the [OT Sandbox Deployment Guide](./deploy-ot-sandbox.md)).
   * **Revision:** Enter `main` (or a specific commit hash/branch name).
4. Click **Save**.
5. Once imported, the portal will automatically validate the YAML syntax. Click on the definition name to view the visual graph representation of your networks (`mgmt-net`, `ot-net`) and hosts (`attacker-host`, `scada-hmi`, `openplc-node`).

---

## Step 2: Create and Allocate the Sandbox Pool

The **Sandbox Pool** is the actual set of VMs spawned inside OpenStack. To instantiate the pool:

1. In the left sidebar, navigate to **Sandboxes** > **Pools**.
2. Click the **Create Pool** button in the top-right corner.
3. Fill in the allocation details:
   * **Name:** Give your pool a recognizable name (e.g., `OT-WaterTank-Lab-Pool`).
   * **Sandbox Definition:** Select the definition you imported in Step 1.
   * **Size:** Enter the number of isolated sandboxes to build (e.g., `1` for self-testing, or more if setting up a training session for multiple students).
4. Click **Save**.
5. Click **Allocate** on the newly created pool.
   * **What happens now:** The platform calls OpenTofu/Terraform internally to build the OpenStack networks, routers, and VMs. It then runs Ansible scripts to install Node-RED and OpenPLC on the nodes.
   * *Status Indicator:* The pool status will transition from `Allocating` to `Active` (this takes about 5–10 minutes depending on internet speeds).

---

## Step 3: Accessing the OT Virtual Machines

Once the Sandbox Pool status is **Active**, you can interact with the virtual machines:

1. Click on your active pool name (`OT-WaterTank-Lab-Pool`).
2. Go to the **Sandboxes** tab.
3. Click the **Show** button next to your active sandbox ID.
4. **Interactive Topology Map:** The page will display a live map of your networks.
5. **Accessing Consoles (Guacamole):**
   * Click on any host (e.g., `scada-hmi` or `attacker-host`).
   * Click the **Web Console** link.
   * A new browser tab will open using the integrated Apache Guacamole client, giving you full interactive remote control (VNC/SSH) over the virtual machine directly within your browser window. No external clients are required.

---

## Step 4: Configuring the SCADA/HMI and PLC Simulators

Once inside your VM consoles:

1. **Verify OpenPLC (local control):**
   * On the host or inside the VM, OpenPLC will be running. You can access the OpenPLC web interface at `http://192.168.99.10:8080` (default login: `openplc` / `openplc`).
   * Here you can write and upload Ladder Logic (`.st` files) representing your industrial water pump control.
2. **Verify Node-RED (SCADA HMI):**
   * Access the Node-RED flow builder at `https://<YOUR_CLUSTER_IP>/grafana` or direct Node-RED port.
   * Configure a Modbus node to read/write holding registers at the PLC's IP address (`192.168.99.10:502`) to display sensor data and control switches on the dashboard.

---

## Step 5: Clean Up / Deleting the Sandbox Pool

To free up CPU and RAM on your server when you are done:

1. Go to **Sandboxes** > **Pools**.
2. Select your pool and click **Delete**.
3. Confirm the deletion.
   * **What happens:** KYPO automatically runs Terraform destroy tasks in OpenStack to delete all VMs, floating IPs, and subnets. Your host resources will be immediately freed up.
