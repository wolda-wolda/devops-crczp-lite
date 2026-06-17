# Agent Handover & Repository Knowledge Base (`Agents.md`)

This file contains crucial context about the `devops-crczp-lite` repository, its architecture, recent modifications, configurations, and operations. It serves to quickly bootstrap future AI agents or developer sessions.

---

## 1. Repository Context & Topology
* **Purpose:** Deploys the **CyberRangeCZ Platform Lite** (an open-source cybersecurity training range based on the KYPO Cyber Range Platform).
* **Architecture:**
  ```text
  Host (KVM/Libvirt)
  └── Parent VM (ubuntu-24.04 via Vagrant-libvirt, Hostname: 'openstack')
      ├── OpenStack Control Plane (Kolla-Ansible stable/2025.1 inside Docker)
      └── Kubernetes Cluster (k3s inside an OpenStack VM instance)
          └── CyberRangeCZ Core microservices (Keycloak, Grafana, Portal, etc.)
  ```

---

## 2. Resource Allocation & Hardware Profile
To prevent host memory exhaustion (OOM) and heavy swapping (which locks up KVM virtual machine scheduling), the `Vagrantfile` implements dynamic resource boundaries based on host specifications:

### Resource Allocation Rules (Dynamic):
* **vCPUs:** Allocates `host_cpus - 4` (leaves 4 cores headroom for host OS, hypervisor emulation, and SSH).
* **RAM:** Allocates `host_ram_mb - 8192` (leaves 8 GB memory buffer for host processes to prevent thrashing).
* *Example (for 32-core, 64 GB host):* Allocates **28 vCPUs** and **~52 GB RAM** to the VM.

### Hypervisor Performance Settings (`Vagrantfile`):
* **`libvirt.cpu_mode = 'host-passthrough'`**: Passes the host's actual CPU instruction set directly to the VM. Exposes AES-NI, AVX, etc. Crucial for nested VMs inside OpenStack to run at near-native speed.
* **`libvirt.disk_driver :cache => 'unsafe'`**: Enables asynchronous write caching on the host side, giving a **2x–5x write performance boost** during package installs, container downloads, and database updates.

---

## 3. Operations & Lifecycle Commands

### Graceful Shutdown
Always stop nested instances before halting the VM to prevent database or filesystem corruption:
1. Log in: `vagrant ssh`
2. Elevate to root: `sudo -i`
3. Load credentials: `source /etc/kolla/admin-openrc.sh`
4. Stop nested VMs:
   ```bash
   for server in $(/root/kolla-ansible-venv/bin/openstack server list -f value -c ID); do
     /root/kolla-ansible-venv/bin/openstack server stop $server
   done
   ```
5. Exit back to the host shell, then run:
   ```bash
   vagrant halt
   ```

### Graceful Startup
1. Boot the VM from the host:
   ```bash
   vagrant up
   ```
   *(Docker and k3s start automatically; OpenStack containers recover automatically via Docker restart policies).*
2. To start the nested sandbox VMs, SSH in, elevate to root, source the OpenStack credentials, and run:
   ```bash
   for server in $(/root/kolla-ansible-venv/bin/openstack server list -f value -c ID); do
     /root/kolla-ansible-venv/bin/openstack server start $server
   done
   ```

---

## 4. Key Endpoints & Credentials
Run these helper commands **from the host** to fetch active credentials:
* **OpenStack Password:** `vagrant ssh -c "sudo grep OS_PASSWORD /etc/kolla/admin-openrc.sh"`
* **Grafana Password:** `vagrant ssh -c "sudo tofu -chdir=/root/devops-tf-deployment/tf-head-services output -raw monitoring_admin_password"`
* **Keycloak Password:** `vagrant ssh -c "sudo tofu -chdir=/root/devops-tf-deployment/tf-head-services output -raw keycloak_password"`
* **Cluster Management IP:** `vagrant ssh -c "sudo tofu -chdir=/root/devops-tf-deployment/tf-openstack-base output -raw cluster_ip"`

| Service / Interface | URL Endpoint | Credentials |
|---|---|---|
| **OpenStack Horizon** | `http://10.1.2.9/` (HTTP) | Username: `admin` |
| **CyberRange Portal** | `https://<cluster_ip>/` (HTTPS) | `crczp-admin` / `password` |
| **Keycloak IAM** | `https://<cluster_ip>/keycloak/` | Username: `admin` |
| **Grafana Dashboard** | `https://<cluster_ip>/grafana` | Username: `admin` |
| **Prometheus API** | `https://<cluster_ip>/prometheus/` | Basic Auth (`admin`) |

---

## 5. Directory Mapping & Reference Docs

* [docs/base-boxes-management.md](file:///opt/cyber-range/devops-crczp-lite/docs/base-boxes-management.md): Describes pre-registered OS images (`debian-12-x86_64`, `ubuntu-noble-x86_64`, `kali`, `cirros`) and how to build/upload custom images.
* [docs/deploy-ot-sandbox.md](file:///opt/cyber-range/devops-crczp-lite/docs/deploy-ot-sandbox.md): Explains how to structure a KYPO sandbox topology YAML file and configure provisioning.
* [docs/deploy-ot-scenario-portal.md](file:///opt/cyber-range/devops-crczp-lite/docs/deploy-ot-scenario-portal.md): A step-by-step portal GUI guide to import, allocate, and delete sandbox pools.
* [docs/deployment-flow.md](file:///opt/cyber-range/devops-crczp-lite/docs/deployment-flow.md): High-level flow description of Phase 1 to Phase 4 script provisioning.
* [docs/infrastructure-reference.md](file:///opt/cyber-range/devops-crczp-lite/docs/infrastructure-reference.md): Lists software packages, snap tools, KVM specs, and access networks.

---

## 6. Topology Definition (`topology.yml`) Schema Reference
To avoid parser validation errors (e.g., `Error parsing <class 'crczp.topology_definition.models.TopologyDefinition'>`), you **must** adhere to the following schema constraints:
* **Flat Root Structure:** Do NOT wrap the configuration in a `kypo_topology:` key. Root keys (`name`, `hosts`, `routers`, `networks`, `net_mappings`, `router_mappings`, `groups`) must be defined directly at the root level of the YAML file.
* **Mandatory Groups Attribute:** The `groups` attribute is required and has no default value. You must define at least one group listing the relevant hosts/routers (e.g., `nodes: [attacker-host, scada-hmi, ...]`).
* **Sibling Flavor Nesting:** `flavor` is a direct sibling of `base_box` (under `hosts` and `routers`), NOT nested inside the `base_box` block.
* **Base Box Image Attribute:** Always define the box image as `image: <image-name>` inside the `base_box` mapping (e.g., `image: debian-12-x86_64`), not as dynamic keys or versions.
* **Explicit Mappings:** Connect hosts via the `net_mappings` list (keys: `host`, `network`, `ip`) and routers via the `router_mappings` list (keys: `router`, `network`, `ip`). The old `mappings` key is not valid.
* **No Router CIDRs:** Routers do not accept a CIDR configuration directly. Define their IPs on each network using the `router_mappings` section.

