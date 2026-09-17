# CyberRangeCZ OT Sandbox & Scenario Upload Guide

This guide describes how to author, package, and deploy Operational Technology (OT) sandboxes and interactive training scenarios to the CyberRangeCZ Platform.

---

## 1. Structure of a Sandbox Definition

A sandbox definition repository consists of three core components:

```text
ot-sandbox/
├── topology.yml          # Declarative OpenStack VM and network topology definition
├── training.json         # Interactive exercise definition (levels, flags, hints, scoring)
└── provisioning/         # Software provisioning playbooks
    ├── playbook.yml      # Master Ansible playbook
    └── roles/            # Ansible roles for node configuration (OpenPLC, Node-RED, etc.)
```

---

## 2. Authoring the Topology (`topology.yml`)

`topology.yml` defines the networks, routers, base images, flavors, and IP mappings for OpenStack Heat.

### Single-Homing Rule (Critical):
To prevent the CyberRangeCZ web visualizer graph engine from crashing, **all non-router host VMs must be single-homed** (connected to exactly one network mapping). Inter-subnet routing must be handled through the router host (`purdue-gateway` / `ot-router`).

### Sample `topology.yml` Schema:
```yaml
name: simple-ot-sandbox

hosts:
  - name: attacker-host
    base_box:
      image: kali
      mgmt_user: debian
    flavor: kali

  - name: scada-hmi
    base_box:
      image: debian-12-x86_64
      mgmt_user: debian
    flavor: ot.hmi

  - name: openplc-node
    base_box:
      image: debian-12-x86_64
      mgmt_user: debian
    flavor: ot.plc

routers:
  - name: ot-router
    base_box:
      image: debian-12-x86_64
      mgmt_user: debian
    flavor: ot.router

networks:
  - name: mgmt-net
    cidr: 10.10.10.0/24
  - name: ot-net
    cidr: 192.168.99.0/24

net_mappings:
  - host: attacker-host
    network: mgmt-net
    ip: 10.10.10.50
  - host: scada-hmi
    network: mgmt-net
    ip: 10.10.10.10
  - host: openplc-node
    network: ot-net
    ip: 192.168.99.10

router_mappings:
  - router: ot-router
    network: mgmt-net
    ip: 10.10.10.1
  - router: ot-router
    network: ot-net
    ip: 192.168.99.1

groups:
  - name: ot-group
    nodes:
      - attacker-host
      - scada-hmi
      - openplc-node
```

---

## 3. Uploading Scenarios via the CyberRangeCZ Portal

1. Log into the CyberRangeCZ Portal at `https://<cluster_ip>/` with admin credentials (`crczp-admin` / `password`).
2. Navigate to **Training Definition** $\rightarrow$ **Upload Training Definition**.
3. Select your scenario's `training.json` file.
4. Link the Git repository URL containing `topology.yml` and `provisioning/`.
5. Click **Release Training Definition** to make the scenario available for active training pools.
