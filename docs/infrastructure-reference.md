# CyberRangeCZ Platform Lite — Infrastructure Reference

> **Source repository:** `devops-crczp-lite`
> **Last audited:** 2026-06-09

---

## 1. Base VM Image

| Property | Value |
|---|---|
| **Vagrant box** | `bento/ubuntu-24.04` |
| **Box version** | `202508.03.0` |
| **Guest OS** | Ubuntu 24.04 LTS (Noble Numbat) |
| **Hostname** | `openstack` |
| **Disk size** | 250 GB (expanded on boot via `growpart` + `lvextend`) |
| **Volume group** | `ubuntu-vg / ubuntu-lv` (LVM, grows to fill virtual disk) |

> The disk image starts smaller; `scripts/01-system-setup.sh` automatically resizes the
> partition and filesystem on first boot.

---

## 2. Hardware / Sizing Requirements

| Resource | Recommended | Minimum |
|---|---|---|
| vCPU | 8 | 4 |
| RAM | 48 GB | 48 GB |
| HDD | 250 GB | 250 GB |

By default, the `Vagrantfile` automatically and dynamically detects the host's hardware capacity:
- **vCPU**: 
  - If `host_cpus > 8`: Allocates `host_cpus - 4` (leaving 4 cores headroom).
  - If `host_cpus > 4`: Allocates `host_cpus - 2`.
  - Else: Allocates all `host_cpus`.
- **RAM**: 
  - If `host_ram_mb > 16384`: Allocates `host_ram_mb - 8192` (leaving 8 GB headroom to prevent host swapping).
  - If `host_ram_mb > 8192`: Allocates `host_ram_mb - 4096` (leaving 4 GB headroom).
  - Else: Allocates all `host_ram_mb`.

For example, on a 32-core, 64 GB RAM server, Vagrant automatically provisions **28 vCPUs** and **~52 GB (52,248 MB) RAM** to the VM.

You can still manually override these dynamic defaults using environment variables:

```bash
CPU=8 RAM=45056 vagrant up
```

### 2.1 Performance Tuning and Hypervisor Settings

To speed up deployment time, several hypervisor-level performance options are enabled by default in the `Vagrantfile`'s Libvirt block:

| Setting | Value | Rationale / Performance Gain | Upsides | Downsides / Risks |
|---|---|---|---|---|
| **vCPU Allocation** | `28` (on 32-core host) | Higher parallelism during Ansible tasks, container image building, and multi-threaded script execution. | Maximize host CPU utilization, decreasing compute-bound phases by 10-15%. | Leaves 4 host cores for host tasks (SSH, basic monitoring, hypervisor overhead). |
| **RAM Allocation** | `~49.5 GB` (on 64 GB host) | Large buffer for OpenStack components, MariaDB cache, RabbitMQ queues, and nested k3s VMs, preventing disk swap. | Minimizes VM out-of-memory errors and disk paging. | Leaves 10 GB RAM for the host OS to prevent OOM/swapping on host hypervisor. |
| **`cpu_mode`** | `'host-passthrough'` | Direct exposure of the host's CPU instruction set (AES-NI, AVX, etc.). Crucial for nested VMs. | **Near bare-metal speed** for nested virtualization (k3s VMs inside OpenStack) and cryptographic handshake performance. | Limits VM live migration capability to hosts with different CPU models (rarely needed for local test setups). |
| **`volume_cache`** | `'unsafe'` | Asynchronous host-backed cache ignoring sync/fsync operations. | **Huge write performance boost (2x–5x)** during disk-intensive phases (package installations, container downloads, database writes). | Data loss in case of physical host power failure (not an issue for short-lived, redeployable test-environments). |

---

## 3. Supported Deployment Platforms

| Platform | Notes |
|---|---|
| Physical server | Primary target |
| Desktop / workstation | Fully supported |
| VM with nested virtualization | Must enable nested virt on the hypervisor |
| **GCP `n2-highmem-4`** | Minimum cloud size; nested virt enabled via `advanced_machine_features` |
| **GCP `n2-highmem-8`** | Recommended cloud size |

GCP deployments use the Terraform code in `tf-gcp-vm/`.

---

## 4. Host-Level Prerequisites

These packages must be present on the **host** before calling `vagrant up`:

```bash
sudo apt install -y qemu-kvm libvirt-daemon libvirt-clients bridge-utils virt-manager docker.io
```

| Package | Role |
|---|---|
| `qemu-kvm` | KVM hypervisor back-end |
| `libvirt-daemon` | Libvirt management daemon |
| `libvirt-clients` | `virsh` CLI |
| `bridge-utils` | Network bridging |
| `virt-manager` | Optional GUI |
| `docker.io` | Required to run the `vagrantlibvirt/vagrant-libvirt` container |

Vagrant itself is **not** installed locally; it runs inside Docker:

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

## 5. Virtualization Layer (KVM / libvirt)

| Property | Value |
|---|---|
| **Provider** | `libvirt` (via `vagrant-libvirt` plugin) |
| **Nested virtualization** | `libvirt.nested = true` — required for OpenStack's internal VMs |
| **Virtual disk** | 250 GB, grows on boot |

Network interfaces inside the VM:

| Interface | IP | Purpose |
|---|---|---|
| `eth0` | DHCP (Vagrant management) | Vagrant SSH / provisioning |
| `eth1` | `10.1.2.10` | OpenStack internal management (`network_interface`) |
| `eth2` | `10.1.2.11` (no auto-config) | Neutron external interface for tenant networks |

---

## 6. OpenStack Orchestrator

### 6.1 Deployment Tool — Kolla-Ansible

| Property | Value |
|---|---|
| **Deployment tool** | Kolla-Ansible |
| **Kolla-Ansible branch** | `stable/2025.1` (OpenStack **Dalmatian** release) |
| **Install source** | `git+https://opendev.org/openstack/kolla-ansible@stable/2025.1` |
| **Ansible core version** | `>=2.17, <2.18.99` |
| **Python venv** | `/root/kolla-ansible-venv` |
| **Install type** | `source` (built from source, not pre-built packages) |
| **Base distro** | `ubuntu` (Kolla container images are Ubuntu-based) |
| **Inventory** | `all-in-one` (single-node deployment) |

### 6.2 Key `globals.yml` Settings

| Key | Value | Notes |
|---|---|---|
| `network_interface` | `eth1` | Management / API network |
| `kolla_base_distro` | `ubuntu` | Container image OS |
| `kolla_install_type` | `source` | Built from source |
| `enable_heat` | `no` | Orchestration service disabled |
| `kolla_internal_vip_address` | `10.1.2.9` | OpenStack API / Horizon endpoint |
| `neutron_external_interface` | `eth2` | Provider network interface |

### 6.3 OpenStack Client

| Property | Value |
|---|---|
| **Package** | `python-openstackclient` |
| **Constraints file** | `https://releases.openstack.org/constraints/upper/2025.1` |
| **Credentials file** | `/etc/kolla/admin-openrc.sh` (auto-sourced in root's `.bashrc`) |

### 6.4 Central Access Points and Endpoints

All services deployed in the cyberrange (both the OpenStack infrastructure layer and the Kubernetes/k3s application layer) are exposed via specific IP addresses, ports, and paths.

#### 1. OpenStack Infrastructure Services (HTTP - Port 80)
These are hosted on the OpenStack Virtual IP (`10.1.2.9`):

| Service / Interface | URL | Port | Access Details / Credentials |
|---|---|---|---|
| **Horizon Dashboard** | `http://10.1.2.9` | 80 | OpenStack web administrative panel. Username: `admin` |
| **Keystone API** | `http://10.1.2.9:5000` | 5000 | OpenStack identity service API endpoint. |
| **Glance API** | `http://10.1.2.9:9292` | 9292 | OpenStack image service API endpoint. |
| **Nova API** | `http://10.1.2.9:8774` | 8774 | OpenStack compute service API endpoint. |

> [!TIP]
> To retrieve the OpenStack `admin` password from your host, run:
> ```bash
> vagrant ssh -c "sudo grep OS_PASSWORD /etc/kolla/admin-openrc.sh"
> ```

#### 2. CyberRange Portal & Application Services (HTTPS - Port 443)
These are hosted on the Kubernetes cluster master IP (`<cluster_ip>`) and routed via the Traefik ingress controller:

| Service / Interface | URL Path | Port | Username / Password Retrieval |
|---|---|---|---|
| **CyberRange Portal (Web UI)** | `https://<cluster_ip>/` | 443 | `crczp-admin` / `password` |
| **Keycloak Auth Server** | `https://<cluster_ip>/keycloak/` | 443 | `admin` / `vagrant ssh -c "sudo tofu -chdir=/root/devops-tf-deployment/tf-head-services output -raw keycloak_password"` |
| **Grafana Dashboard** | `https://<cluster_ip>/grafana` | 443 | `admin` / `vagrant ssh -c "sudo tofu -chdir=/root/devops-tf-deployment/tf-head-services output -raw monitoring_admin_password"` |
| **Prometheus API** | `https://<cluster_ip>/prometheus/` | 443 | Requires basic authentication using `admin` credentials (same password as Grafana). |
| **Alertmanager** | `https://<cluster_ip>/alerts/` | 443 | Requires basic authentication using `admin` credentials. |

> [!NOTE]
> The `<cluster_ip>` is the internal floating IP of the Kubernetes management node in your OpenStack deployment. You can output this IP from your host using:
> ```bash
> vagrant ssh -c "sudo tofu -chdir=/root/devops-tf-deployment/tf-openstack-base output -raw cluster_ip"
> ```

---

## 7. Kubernetes (k3s)

Kubernetes is deployed **inside** OpenStack via the `devops-tf-deployment` Terraform repository.

| Property | Value |
|---|---|
| **Distribution** | k3s (lightweight Kubernetes) |
| **Deployment repo** | `https://github.com/cyberrangecz/devops-tf-deployment` |
| **Pinned tag** | `v1.4.0` |
| **Terraform module** | `tf-openstack-base` |
| **API endpoint** | `https://<cluster_ip>:6443/` |
| **kubeconfig** | `/root/.kube/config` |
| **CRD readiness signal** | `middlewares.traefik.io` (Traefik ingress controller) |

### Terraform Variables — Base Infrastructure

| Variable | Value | Notes |
|---|---|---|
| `external_network_name` | `public1` | OpenStack external network |
| `dns_nameservers` | `["$DNS1","$DNS2"]` | Defaults: `1.1.1.1`, `1.0.0.1` |
| `standard_small_disk` | `10` GB | Small flavor disk size |
| `standard_medium_disk` | `16` GB | Medium flavor disk size |

### Terraform Variables — Head Services

| Variable | Value |
|---|---|
| `man_flavor` | `standard.medium` |
| `gen_user_count` | `10` |
| `enable_monitoring` | `true` |
| `acme_contact` | `demo@example.com` |
| `openid_configuration_insecure` | `true` |
| `os_region` | `RegionOne` |

---

## 8. GCP Terraform Provider (`tf-gcp-vm/`)

| Property | Value |
|---|---|
| **Provider** | `hashicorp/google` |
| **Locked version** | `4.21.0` |
| **TLS provider version** | `3.4.0` |
| **GCP project** | `crczp-lite` |
| **Region / Zone** | `europe-west3` / `europe-west3-c` |
| **Machine type** | `n2-highmem-8` |
| **Boot image** | `ubuntu-2004-focal-v20220419` (Ubuntu **20.04** LTS) |
| **Boot disk size** | 250 GB |
| **Nested virtualization** | Enabled (`enable_nested_virtualization = true`) |
| **Firewall** | TCP/22 open to `0.0.0.0/0` |
| **Auth** | `auth.json` service account key file |

> **⚠️ OS mismatch:** The GCP boot image is Ubuntu **20.04**, while the Vagrant box uses
> Ubuntu **24.04**. Verify script compatibility before deploying via this path.

---

## 9. CLI Tools Installed in the Vagrant VM

### Snap Packages

| Tool | Flag | Purpose |
|---|---|---|
| `opentofu` | `--classic` | OpenTofu (Terraform-compatible IaC) |
| `kubectl` | `--classic` | Kubernetes CLI |
| `helm` | `--classic` | Kubernetes package manager |

### APT Packages

| Package | Purpose |
|---|---|
| `python3-dev` | Python C extension headers |
| `libffi-dev` | Foreign function interface (required by Kolla) |
| `gcc` | C compiler |
| `libssl-dev` | SSL/TLS development libraries |
| `python3-venv` | Python virtual environment support |
| `python3-docker` | Docker Python SDK |
| `pipenv` | Python environment management |
| `jq` | JSON query tool (used in credential extraction) |
| `ca-certificates` | Reinstalled to fix potential SSL trust issues |

---

## 10. Ansible Configuration

File: `ansible.cfg`

| Setting | Value | Notes |
|---|---|---|
| `host_key_checking` | `False` | Skips SSH host key verification |
| `pipelining` | `True` | Reduces SSH round trips (performance) |
| `forks` | `100` | High parallelism for Kolla playbooks |

---

## 11. Network Topology

```
Host (bare metal / GCP)
└── KVM / libvirt
    └── Vagrant VM  bento/ubuntu-24.04  10.1.2.10
        ├── eth1: 10.1.2.10  →  OpenStack management / API
        ├── eth2: 10.1.2.11  →  Neutron external (provider network)
        └── OpenStack (Kolla-Ansible 2025.1, VIP: 10.1.2.9)
            └── k3s Kubernetes cluster
                └── CyberRangeCZ Platform (head services)
```

Full subnet `10.1.2.0/24` is routable from the host. For remote hosts use:

```bash
sshuttle -r root@<host> 10.1.2.0/24
```

---

## 12. Provisioning Pipeline

| Phase | Script | Est. duration | Description |
|---|---|---|---|
| 1 | `scripts/01-system-setup.sh` | ~5 min | Disk expand, DNS, snap/APT packages, SSH |
| 2 | `scripts/02-openstack-deploy.sh` | 30–60 min | Kolla-Ansible install + OpenStack deploy |
| 3 | `scripts/03-infrastructure-deploy.sh` | 35–70 min | OpenTofu base infra, k3s, head services |
| 4 | `scripts/04-final-setup.sh` | ~1 min | Service check, display portal URL, cleanup |

---

## 13. Default Credentials

| Service | Username | Password / Retrieval Command (Run from Host) |
|---|---|---|
| CyberRangeCZ Portal | `crczp-admin` | `password` |
| OpenStack Horizon | `admin` | `vagrant ssh -c "sudo grep OS_PASSWORD /etc/kolla/admin-openrc.sh"` |
| Grafana monitoring | `admin` | `vagrant ssh -c "sudo tofu -chdir=/root/devops-tf-deployment/tf-head-services output -raw monitoring_admin_password"` |
| Keycloak admin | `admin` | `vagrant ssh -c "sudo tofu -chdir=/root/devops-tf-deployment/tf-head-services output -raw keycloak_password"` |
| OpenStack app credential | `demo` | `password` |

> [!NOTE]
> If you are running Vagrant inside the Docker wrapper, run the commands using the docker container:
> ```bash
> # Example to retrieve the OpenStack Horizon admin password:
> docker run -it --rm \
>   -v /var/run/libvirt/:/var/run/libvirt/ \
>   -v ~/.vagrant.d:/.vagrant.d \
>   -v $(realpath "${PWD}"):${PWD} \
>   -w "${PWD}" \
>   --network host \
>   vagrantlibvirt/vagrant-libvirt:latest \
>   vagrant ssh -c "sudo grep OS_PASSWORD /etc/kolla/admin-openrc.sh"
> ```

---

## 14. Related Documentation

- [OT Sandbox Deployment Guide](./deploy-ot-sandbox.md) — Step-by-step guide for deploying Node-RED HMI and OpenPLC
- [OT Sandbox Portal Guide](./deploy-ot-scenario-portal.md) — Step-by-step guide on importing and allocating sandboxes in the Portal UI
- [Base Boxes & Image Management Guide](./base-boxes-management.md) — Sourcing and uploading OS images to OpenStack Glance
