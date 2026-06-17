# CyberRangeCZ Base Boxes & VM Image Management

In the CyberRangeCZ / KYPO platform, virtual machines created within a sandbox are launched from base OS images stored in **OpenStack Glance**. In the topology definitions (`topology.yml`), these images are referenced by the `base_box` field.

This guide explains how to build, download, and register these base boxes in the platform's OpenStack backend.

---

## 1. Pre-registered Platform Images (Out-of-the-Box)

The CyberRangeCZ platform's default infrastructure deployment (`tf-openstack-base`) automatically registers and downloads standard OS images from remote sources.

**This means you do NOT need to manually build or register any new OS images to run standard sandbox templates or the simple OT sandbox tutorial.**

| Image Name in Glance | OS / Distribution | Download Size | Virtual Format | Primary Role |
|---|---|---|---|---|
| **`cirros`** | CirrOS Linux | ~20 MB | QCOW2 | Lightweight testing VM |
| **`debian-12-x86_64`** | Debian 12 (Bookworm) | ~333 MB | QCOW2 | Infrastructure & PLC VM |
| **`ubuntu-noble-x86_64`** | Ubuntu 24.04 LTS | ~598 MB | QCOW2 | Kubernetes nodes, general Linux servers |
| **`kali`** | Kali Linux (Attacker) | ~18.2 GB | QCOW2 | Attacker workstation (Red Team) |
| **`ubuntu-noble-man`** *(Optional)* | Ubuntu 24.04 LTS | ~2 GB | QCOW2 | Desktop Workstation (Engineering) |

---

### Detailed Image Reference

#### 1. `cirros`
* **Download Size:** 20.44 MB
* **Preinstalled Software:** Minimal busybox shell utilities, basic network tools.
* **Cyber Range Role:** **Sanity Testing.** Used to quickly test network routing, floating IP allocation, security groups, and basic instance booting without waiting for larger downloads.
* **GUI Support:** None (serial console only).

#### 2. `debian-12-x86_64`
* **Download Size:** 333.56 MB
* **Preinstalled Software:** `cloud-init`, Python 3, OpenSSH server, standard Debian core utils.
* **Cyber Range Role:** **Infrastructure & Services.** This is a headless, highly optimized server image. Ideal for deploying lightweight networking components, database servers, and virtualized industrial controllers like **OpenPLC nodes**.
* **GUI Support:** None (SSH only).

#### 3. `ubuntu-noble-x86_64`
* **Download Size:** 598.83 MB
* **Preinstalled Software:** `cloud-init`, Python 3, OpenSSH, systemd-resolved, standard Ubuntu Server core.
* **Cyber Range Role:** **Cluster Node & General Workloads.** The base image for your jump/proxy hosts (`proxy-jump`) and your Kubernetes (`k3s`) cluster instances. It provides a modern, secure base OS for running containerized pods and general applications.
* **GUI Support:** None (SSH only).

#### 4. `kali`
* **Download Size:** 18.2 GB (Downloads in background via Glance)
* **Preinstalled Software:** 
  * **Desktop GUI:** XFCE desktop environment.
  * **Security Suites:** `Metasploit Framework`, `Nmap` / `Zenmap`, `Wireshark`, `Burp Suite`, `John the Ripper`, `Hydra`, `Aircrack-ng`, `Ghidra`, `Sqlmap`, `Hashcat`.
  * **Databases:** PostgreSQL (configured for Metasploit backend).
  * **Resources:** Dictionary files and wordlists (e.g., `rockyou.txt` in `/usr/share/wordlists/`).
* **Cyber Range Role:** **Attacker / Red Team Workstation.** Spawns as the central hub where students/auditors log in (via browser-based Guacamole VNC) to run security tools, scan the subnet, and exploit vulnerabilities.
* **GUI Support:** Full XFCE desktop interface, accessible via VNC/Spice/RDP through the cyberrange portal.

#### 5. `ubuntu-noble-man` *(Disabled by default)*
* **Download Size:** ~2.1 GB
* **Preinstalled Software:** Full GNOME / Ubuntu Desktop environment, system utilities. (Can be enabled by setting `import_noble_man = true` in OpenTofu variables).
* **Cyber Range Role:** **Desktop Client Workstation (Blue Team / Engineering).** Provides a standard, graphical Linux environment for engineers or defenders to interact with HMIs, configure PLCs, or monitor SIEM consoles.
* **GUI Support:** Full desktop interface, accessible via browser console.

---

## 2. Sourcing Custom Base Boxes

If you require custom or specialized operating systems (such as a Windows Engineering Workstation) that are not pre-registered, you can obtain them using two methods:

### Method A: Build Custom Images with Packer (Recommended)
Building images with Packer ensures full compatibility with the range's provisioning services. The platform developers maintain pre-configured Packer templates that automatically set up `cloud-init`, Python dependencies, and SSH keys.

* **Official Repository:** [MUNI-KYPO Images GitLab](https://gitlab.ics.muni.cz/muni-kypo-images)
* **Build Workflow:**
  1. Install Packer on your build machine: `sudo apt install packer`.
  2. Clone the template repository for your desired OS (e.g., `debian`, `ubuntu`, `windows`).
  3. Execute the build command:
     ```bash
     packer build template.pkr.hcl
     ```
  4. The output will be an optimized virtual disk file (typically in `.qcow2` format).

### Method B: Download Public Cloud Images
You can use standard, minimal cloud-ready images directly from Linux distributions. Make sure you download the **QCOW2** disk format containing `cloud-init` support:

* **Ubuntu Cloud Images:** [https://cloud-images.ubuntu.com/](https://cloud-images.ubuntu.com/)
* **Debian Cloud Images:** [https://cloud.debian.org/images/cloud/](https://cloud.debian.org/images/cloud/)
* **AlmaLinux Cloud Images:** [https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/](https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/)

---

## 3. Registering Custom Images in OpenStack (Glance)

Once you have downloaded or compiled the `.qcow2` image, you must load it into OpenStack so it is discoverable by the cyberrange.

### Option 1: Via the OpenStack Command Line (CLI)
Source the OpenStack admin environment variables inside the primary control node and upload the image:

```bash
# 1. Source OpenStack credentials
source /etc/kolla/admin-openrc.sh

# 2. Upload the QCOW2 disk image
openstack image create "debian-11-x86_64" \
  --file ./debian-11-generic-amd64.qcow2 \
  --disk-format qcow2 \
  --container-format bare \
  --public
```

### Option 2: Via OpenStack Horizon Web Dashboard
1. Open Horizon in your browser (default endpoint: `http://10.1.2.9`).
2. Navigate to **Project** > **Compute** > **Images**.
3. Click the **Create Image** button at the top right.
4. Set the fields:
   * **Image Name:** Enter the exact identifier (e.g., `ubuntu-22.04-x86_64`).
   * **File:** Browse and upload your local `.qcow2` image.
   * **Format:** Select `QCOW2 - QEMU Emulator`.
   * **Visibility:** Set to `Public` (crucial so that isolated sandbox tenants can boot it).
5. Click **Create Image** and wait for the upload/saving state to complete.

---

## 4. Referencing the Base Box in Sandbox Definitions

In your sandbox's `topology.yml` file, the `base_box` configuration maps directly to the image name in OpenStack Glance:

```yaml
hosts:
  - name: my-workstation
    base_box:
      image: debian-12-x86_64   # Must exactly match the name in Glance
      flavor: standard.small
```

> [!WARNING]
> If the string defined in `image: <name>` does not match any image registered in Glance, the Terraform stage of the Sandbox allocation will fail with an `ImageNotFound` resource creation error.
