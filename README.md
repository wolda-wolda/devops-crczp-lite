# CyberRangeCZ Platform Lite

This repository provides an automated single-host deployment of the **CyberRangeCZ Platform** running on an OpenStack + Kubernetes infrastructure stack.

This is the companion code repository for the Bachelor's thesis "From IT to OT: Feasibility of CyberRangeCZ for Industrial Control System Training." It extends the upstream CyberRangeCZ Lite platform with the OT sandbox scenarios, telemetry/data-collection scripts, and reproducibility artifacts used throughout the thesis.

---

## 📁 Repository Layout

| Path | Contents |
|---|---|
| `scripts/` | Platform deployment scripts (`01`-`04`) plus the thesis's own data-collection and resource-measurement scripts (`collect_*.sh`, `run_steal_time_test.sh`, `update_placement.py`) used for the Chapter 5 sizing and jitter measurements |
| `scenarios/simple-ot-sandbox/` | The baseline two-subnet OT sandbox (`topology.yml`, `training.json`, `provisioning/`) |
| `scenarios/complex-ot-scenario/` | The multi-zone water treatment sandbox detailed in the thesis body (Chapters 3-4) |
| `scenarios/smartgrid-ot-sandbox/` | The smart-grid substation co-simulation sandbox |
| `artifacts/data_dumps/` | Raw telemetry and system-state dumps (RAM, disk, CPU, OpenStack inventory, PCAPs) backing the numbers reported in Chapter 5 |
| `artifacts/screenshots/` | Screenshots used as figures in the thesis |
| `artifacts/archived-training-instance.zip` | One archived end-to-end run of the training scenario (assessment answers, per-level action logs), referenced in the thesis Conclusion |

Note: screen recordings of the provisioning process and attack walkthrough are kept private and are not included in this repository due to their size and are available on request.

---

## 📚 Documentation Index (`docs/`)


All system manuals, deployment guides, troubleshooting tools, and training scenario solutions are located in the [`docs/`](file:///opt/cyber-range/devops-crczp-lite/docs) directory:

| Document | Description |
|---|---|
| 🚀 [**Deployment Guide**](file:///opt/cyber-range/devops-crczp-lite/docs/deployment-guide.md) | Full system setup, hardware sizing, 4-phase script flow, and access credentials |
| 🛡️ [**Sandbox Deployment & Portal Upload Guide**](file:///opt/cyber-range/devops-crczp-lite/docs/sandbox-deployment-guide.md) | Creating `topology.yml`, `training.json`, base boxes, and uploading scenarios |
| 🔑 [**OT Scenarios Solution Manual**](file:///opt/cyber-range/devops-crczp-lite/docs/ot-scenarios-solution-manual.md) | Complete instructor walkthrough and flags for Simple OT, Complex OT, and Smart Grid scenarios |
| 🛠️ [**Troubleshooting Commands**](file:///opt/cyber-range/devops-crczp-lite/docs/troubleshooting-commands.md) | Recovery commands for OpenStack, K8s pods, network bridges, and Heat stacks |
| 📦 [**Base Boxes & Image Management**](file:///opt/cyber-range/devops-crczp-lite/docs/base-boxes-management.md) | Building and importing Kali Linux and Debian 12 guest VM images |
| 📐 [**Training Scenario Schemas**](file:///opt/cyber-range/devops-crczp-lite/docs/training-scenario-schemas.md) | Technical YAML/JSON schemas for topology definitions and training exercises |
| 📊 [**Command Tracking & Assessment Engine**](file:///opt/cyber-range/devops-crczp-lite/docs/command-tracking-and-assessment.md) | Student command tracking and automated scoring documentation |

---

## ⚡ Quick Start Deployment

### System Requirements:
* **Host OS**: Ubuntu 24.04 LTS
* **Hardware**: 8 vCPUs, 48 GB RAM, 250 GB HDD (Minimum: 4 vCPUs, 48 GB RAM)

### One-Command Deployment:
```bash
sudo apt update && sudo apt install -y qemu-kvm libvirt-daemon libvirt-clients bridge-utils virt-manager docker.io

# (Optional) Set your GitHub Personal Access Token to avoid GitHub API rate limits
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

### 🔑 Note on GitHub Personal Access Token (PAT) for Handover:
When pulling scenario repositories or Helm/OpenTofu provider modules from GitHub, unauthenticated requests may encounter API rate limits (`429 Too Many Requests`).
To set or update your own GitHub PAT on an existing deployment:
1. Generate a classic GitHub PAT (`repo` read access) on [GitHub Token Settings](https://github.com/settings/tokens).
2. Pass `GITHUB_PAT="ghp_..."` when running `vagrant up`, or export it inside the running VM:
   ```bash
   vagrant ssh
   sudo -i
   export GITHUB_PAT="ghp_yourPersonalAccessTokenHere"
   ```

---

## 🌐 Accessing Services

Upon completion of the deployment:
* **CyberRangeCZ Web Portal**: `https://<cluster_ip>/` (Default: `crczp-admin` / `password`)
* **OpenStack Horizon GUI**: `http://10.1.2.9/` (User: `admin` | Password in VM: `grep OS_PASSWORD /etc/kolla/admin-openrc.sh`)

### Remote Access via `sshuttle` (Recommended):
```bash
sshuttle -r root@<remote-host-ip> 10.1.2.0/24
```
