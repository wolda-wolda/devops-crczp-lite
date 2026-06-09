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

## Related Documentation

- [Infrastructure Reference](./infrastructure-reference.md) — VM versions, OS images, tool versions, credentials
