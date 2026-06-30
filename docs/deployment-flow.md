# CyberRangeCZ Platform Lite — Deployment Flow

> **Source repository:** `devops-crczp-lite`
> **Last audited:** 2026-06-09

---

## Overview

The deployment is fully automated via `vagrant up`. It runs four sequential provisioning
scripts inside a KVM virtual machine and results in a fully operational CyberRangeCZ Platform
accessible through a browser.

```
Host → KVM VM (OpenStack) → OpenStack VM (k3s) → Kubernetes pods (CRCZP)
```

Three layers of virtualisation are involved. Nested virtualisation (`libvirt.nested = true`)
is mandatory on the host.

---

## Start: Prerequisites on the Host

Before running `vagrant up`, the host must have:

```bash
sudo apt install -y qemu-kvm libvirt-daemon libvirt-clients bridge-utils virt-manager docker.io
```

Vagrant runs **inside Docker** — no local Vagrant installation is needed:

```bash
docker run -it --rm \
  -e LIBVIRT_DEFAULT_URI \
  -v /var/run/libvirt/:/var/run/libvirt/ \
  -v ~/.vagrant.d:/.vagrant.d \
  -v $(realpath "${PWD}"):${PWD} \
  -w "${PWD}" \
  --network host \
  vagrantlibvirt/vagrant-libvirt:latest \
  vagrant up
```

---

## Phase 1 — System Setup (~5 min)

**Script:** `scripts/01-system-setup.sh`

```
vagrant up
  └─▶ KVM boots bento/ubuntu-24.04 (202508.03.0)
        ├─ growpart /dev/vda 3
        ├─ lvextend + resize2fs  →  disk grows to 250 GB
        ├─ Configure DNS (eth1 / systemd-resolved)
        ├─ snap install opentofu kubectl helm  (--classic)
        ├─ apt install python3-venv python3-dev gcc libffi-dev libssl-dev jq pipenv
        └─ Write /root/.ssh/config  (StrictHostKeyChecking no)
```

The VM is now ready for software installation.

---

## Phase 2 — OpenStack Deployment (30–60 min)

**Script:** `scripts/02-openstack-deploy.sh`

```
/root/kolla-ansible-venv  (Python venv)
  ├─ pip install ansible-core >=2.17,<2.18.99
  ├─ pip install kolla-ansible @ stable/2025.1
  ├─ Configure /etc/kolla/globals.yml
  │     network_interface:        eth1
  │     kolla_internal_vip_address: 10.1.2.9
  │     neutron_external_interface: eth2
  │     kolla_base_distro:        ubuntu
  │     kolla_install_type:       source
  │     enable_heat:              no
  ├─ kolla-ansible bootstrap-servers  -i all-in-one
  ├─ kolla-ansible prechecks          -i all-in-one
  ├─ kolla-ansible deploy             -i all-in-one   ◀ longest step
  ├─ kolla-ansible post-deploy        -i all-in-one
  └─ init-runonce  →  creates default networks, images, flavors
```

OpenStack is now reachable at `http://10.1.2.9` (Horizon) and `http://10.1.2.9` (API).

---

## Phase 3 — Infrastructure Deployment (35–70 min)

**Script:** `scripts/03-infrastructure-deploy.sh`

```
OpenStack app credential  →  OS_APPLICATION_CREDENTIAL_ID / _SECRET

git clone cyberrangecz/devops-tf-deployment @ v1.4.0
  │
  ├─▶ tf-openstack-base  (tofu apply)
  │     Creates inside OpenStack:
  │       ├─ Private network + router
  │       ├─ Security groups
  │       ├─ k3s node VM  →  exposes Kubernetes API at <cluster_ip>:6443
  │       └─ Proxy VM     →  <proxy_host>
  │
  ├─ Copy kubeconfig  →  /root/.kube/config
  ├─ Wait for Traefik CRD  (middlewares.traefik.io)
  │
  └─▶ tf-head-services  (tofu apply)
        Deploys into k3s:
          ├─ Keycloak          →  https://<cluster_ip>/keycloak/
          ├─ Grafana           →  (monitoring_admin_password)
          ├─ CyberRangeCZ API
          └─ CyberRangeCZ Portal web UI
```

---

## Phase 4 — Final Setup (~1 min)

**Script:** `scripts/04-final-setup.sh`

```
├─ openstack service list   →  verify OpenStack is up
├─ kubectl get nodes        →  verify k3s is up
├─ Print deployment summary:
│     URL:      https://<cluster_ip>/
│     Username: crczp-admin
│     Password: password
│     Grafana:  <monitoring_admin_password>
│     Keycloak: <keycloak_password>
└─ apt autoremove + rm /tmp/scripts/
```

---

## End: Access the Platform

Open the printed URL in a browser:

```
https://<cluster_ip>/
```

Log in with `crczp-admin` / `password`.

To tunnel traffic from a remote host:

```bash
sshuttle -r root@<host> 10.1.2.0/24
```

---

## Complete Flow Diagram

```
┌─ Host (Ubuntu 24.04 / GCP n2-highmem-8) ──────────────────────────────┐
│                                                                         │
│  docker run vagrantlibvirt/vagrant-libvirt  →  vagrant up              │
│                                                                         │
│  ┌─ KVM VM  bento/ubuntu-24.04  10.1.2.10 ────────────────────────┐   │
│  │                                                                  │   │
│  │  Phase 1: disk · dns · snaps · apt                              │   │
│  │                                                                  │   │
│  │  Phase 2: Kolla-Ansible                                         │   │
│  │  ┌─ OpenStack (all-in-one, VIP 10.1.2.9) ──────────────────┐   │   │
│  │  │                                                           │   │   │
│  │  │  Phase 3: devops-tf-deployment @ v1.4.0                  │   │   │
│  │  │  ┌─ k3s VM ─────────────────────────────────────────┐    │   │   │
│  │  │  │                                                   │    │   │   │
│  │  │  │  Keycloak · Grafana · CRCZP API · CRCZP Portal   │    │   │   │
│  │  │  │                                                   │    │   │   │
│  │  │  └───────────────────────────────────────────────────┘    │   │   │
│  │  │                                                           │   │   │
│  │  └───────────────────────────────────────────────────────────┘   │   │
│  │                                                                  │   │
│  │  Phase 4: verify · print URL · cleanup                          │   │
│  │                                                                  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

           ▼
  https://<cluster_ip>/   →   CyberRangeCZ Platform  ✓
```

---

## Estimated Total Time

| Phase | Script | Time |
|---|---|---|
| System Setup | `01-system-setup.sh` | ~5 min |
| OpenStack | `02-openstack-deploy.sh` | 30–60 min |
| Infrastructure | `03-infrastructure-deploy.sh` | 35–70 min |
| Final | `04-final-setup.sh` | ~1 min |
| **Total** | | **~70–136 min** |

---

## Graceful Shutdown & Startup Procedures

Because the cyberrange runs virtual machines nested inside OpenStack, and runs multiple database services (PostgreSQL for Keycloak/Guacamole, MariaDB for OpenStack, etc.) inside Docker and Kubernetes, **improper shutdowns can lead to database corruption or broken VM disk states.**

Follow these steps to shut down and boot up the platform cleanly:

### 1. Graceful Shutdown Procedure

#### Step A: Stop Nested OpenStack Sandbox Instances
Before shutting down the parent Vagrant VM, you must gracefully power off all active training sandbox VMs running inside OpenStack.
1. SSH into the Vagrant VM:
   ```bash
   vagrant ssh
   ```
2. Elevate to root and source your OpenStack credentials:
   ```bash
   sudo -i
   source /etc/kolla/admin-openrc.sh
   ```
3. Stop all running instances using the absolute path to the OpenStack client:
   ```bash
   for server in $(/root/kolla-ansible-venv/bin/openstack server list -f value -c ID); do
     /root/kolla-ansible-venv/bin/openstack server stop $server
   done
   ```
4. Exit back to your host machine:
   ```bash
   exit
   exit
   ```

#### Step B: Stop the Vagrant VM (from the Host)
Once the nested guest VMs have stopped, trigger an ACPI graceful shutdown on the parent Vagrant VM from your host:
```bash
vagrant halt
```
* **Why this is safe:** Vagrant will send an ACPI shutdown signal to the Ubuntu guest. The guest OS will trigger systemd to cleanly stop `k3s.service` and `docker.service`. These services send SIGTERM to all database and control plane containers (MariaDB, PostgreSQL, RabbitMQ), giving them a grace period to flush memory transactions to disk before closing.

---

### 2. Graceful Startup Procedure

#### Step A: Boot the Vagrant VM
From the host repository directory, spin up the VM:
```bash
vagrant up
```
* **What happens:** The VM boots. Docker and k3s services are set to start automatically.
* Since the OpenStack containers are configured with a restart policy (`restart: unless-stopped` or `always`), Docker will automatically restart all OpenStack services.

#### Step B: Verify Service Readiness
Wait a few minutes for all API endpoints to initialize. You can check the service statuses inside the VM:
1. Log in:
   ```bash
   vagrant ssh
   ```
2. Check that the containers are running and healthy:
   ```bash
   sudo docker ps
   ```
3. Verify Kubernetes node status:
   ```bash
   kubectl get nodes
   ```

#### Step C: Start Nested OpenStack Sandbox Instances
If you gracefully stopped the sandbox instances during shutdown, you need to turn them back on:
1. Elevate to root and source credentials:
   ```bash
   sudo -i
   source /etc/kolla/admin-openrc.sh
   ```
2. Start all stopped instances using the absolute path to the OpenStack client:
   ```bash
   for server in $(/root/kolla-ansible-venv/bin/openstack server list -f value -c ID); do
     /root/kolla-ansible-venv/bin/openstack server start $server
   done
   ```
3. Exit back to your host machine:
   ```bash
   exit
   exit
   ```

---

## Related Documentation

- [Infrastructure Reference](./infrastructure-reference.md) — VM versions, OS images, tool versions, credentials
- [OT Sandbox Deployment Guide](./deploy-ot-sandbox.md) — Step-by-step guide for deploying Node-RED HMI and OpenPLC
- [OT Sandbox Portal Guide](./deploy-ot-scenario-portal.md) — Step-by-step guide on importing and allocating sandboxes in the Portal UI
- [OT Sandbox Solutions](./ot-sandbox-solutions.md) — Complete training solution walkthrough
- [Complex OT Solutions](./complex-ot-solutions.md) — Walkthrough for the realistic EWS pivot scenario
- [Base Boxes & Image Management Guide](./base-boxes-management.md) — Sourcing and uploading OS images to OpenStack Glance
