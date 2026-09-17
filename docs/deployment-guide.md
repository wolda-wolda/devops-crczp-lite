# CyberRangeCZ Platform Lite — Complete Deployment Guide

This guide provides the complete deployment procedure, system architecture, hardware sizing, and configuration reference for **CyberRangeCZ Platform Lite**.

---

## 1. System Architecture & Virtualization Stack

CyberRangeCZ Lite deploys the entire cyber range infrastructure inside a single virtual machine using three nested virtualization layers:

```text
Host (Ubuntu 24.04 / GCP VM)
  └── KVM VM ("openstack" - 250 GB Disk, 48 GB+ RAM)
        └── Kolla-Ansible OpenStack (VIP: 10.1.2.9)
              └── k3s Kubernetes Node (CRCZP API, Portal, Keycloak, Grafana)
              └── OpenStack Heat Sandbox Instances (OT Training Scenarios)
```

---

## 2. Hardware Sizing & Prerequisites

### Minimum vs Recommended Sizing
| Resource | Minimum | Recommended |
|---|---|---|
| **vCPU** | 4 cores | 8+ cores |
| **RAM** | 48 GB | 48 GB - 64 GB |
| **Storage** | 250 GB HDD | 250 GB SSD / NVMe |

### Host Prerequisites
Before running `vagrant up`, install the KVM and Docker prerequisites on the host machine:

```bash
sudo apt update && sudo apt install -y qemu-kvm libvirt-daemon libvirt-clients bridge-utils virt-manager docker.io
```

Vagrant runs automatically inside Docker container `vagrantlibvirt/vagrant-libvirt:latest`.

---

## 3. Automated 4-Phase Deployment Flow

To provision the platform, run from the repository root:

```bash
# (Optional) Export your GitHub PAT to prevent API rate limiting
export GITHUB_PAT="ghp_yourPersonalAccessTokenHere"

docker run -it --rm \
  -e LIBVIRT_DEFAULT_URI \
  -e GITHUB_PAT \
  -v /var/run/libvirt/:/var/run/libvirt/ \
  -v ~/.vagrant.d:/.vagrant.d \
  -v $(realpath "${PWD}"):${PWD} \
  -w "${PWD}" \
  --network host \
  vagrantlibvirt/vagrant-libvirt:latest \
  vagrant up
```

> 🔑 **GitHub PAT Note for Handover**:
> The `GITHUB_PAT` variable prevents GitHub API rate limits (`429 Too Many Requests`) when fetching Helm/OpenTofu provider modules. If handing over an existing deployment, your colleague can set or update their GitHub PAT inside the VM at any time:
> ```bash
> vagrant ssh
> sudo -i
> export GITHUB_PAT="ghp_yourColleaguesGitHubTokenHere"
> ```

### Script Execution Pipeline:

1. **Phase 1: System Setup (`scripts/01-system-setup.sh`, ~5 min)**
   * Extends root partition LVM disk to 250 GB.
   * Installs core utilities (`OpenTofu`, `kubectl`, `helm`, `python3-pip`, `jq`).

2. **Phase 2: OpenStack Deployment (`scripts/02-openstack-deploy.sh`, ~35 min)**
   * Deploys Kolla-Ansible OpenStack services (Nova, Neutron, Keystone, Glance, Horizon).
   * Configures virtual IP `10.1.2.9` and initializes network bridges.

3. **Phase 3: Platform Infrastructure Deployment (`scripts/03-infrastructure-deploy.sh`, ~35 min)**
   * Provisions `k3s` node inside OpenStack via OpenTofu.
   * Deploys CyberRangeCZ API, Web Portal UI, Keycloak SSO, and Grafana monitoring into Kubernetes.

4. **Phase 4: Verification & Credentials Summary (`scripts/04-final-setup.sh`, ~1 min)**
   * Validates OpenStack and Kubernetes API health.
   * Displays portal access URLs and credentials.

---

## 4. Accessing the Platform & Credentials

Upon deployment completion:
* **CyberRangeCZ Portal**: `https://<cluster_ip>/` (User: `crczp-admin` | Password: `password`)
* **OpenStack Horizon GUI**: `http://10.1.2.9/` (User: `admin` | Password: run `grep "OS_PASSWORD" /etc/kolla/admin-openrc.sh` inside VM)

### Remote Access via `sshuttle` (Recommended):
If running Vagrant on a remote server or cloud host:
```bash
sshuttle -r root@<remote-host-ip> 10.1.2.0/24
```
