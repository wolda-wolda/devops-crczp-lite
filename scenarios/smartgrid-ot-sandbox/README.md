# Operation Blackout Zero - Smart Grid Co-Simulation Sandbox

**Operation Blackout Zero** is a 100% software-emulated, production-ready Smart Grid Co-Simulation Cyber Range package built for **CyberRangeCZ (KYPO CRP)** on OpenStack Heat. It bridges a Level 0 power distribution grid simulation (**GridLAB-D IEEE 13-Node Test Feeder**) with Level 1 Substation logic (**OpenPLC V3**), Level 3 SCADA Control Room monitoring (**Node-RED**, **InfluxDB**, **Grafana**), and an Industrial DMZ (**IDMZ Jump Host**) via a high-performance Python 3 co-simulation bridge (`gridlabd_bridge.py`).

---

## 📚 Package Documentation (`docs/`)

All scenario documentation, architecture maps, solutions, and demo cheatsheets are located in the [`docs/`](file:///opt/cyber-range/smartgrid-ot-sandbox/docs) directory:

| Document | Description |
|---|---|
| 🗺️ [**Architecture & Network Layout**](file:///opt/cyber-range/smartgrid-ot-sandbox/docs/layout.md) | Purdue Model 4-tier subnets, node IP allocations, Modbus register mapping table, and firewall rule matrix |
| 🔑 [**Solution Walkthrough Manual**](file:///opt/cyber-range/smartgrid-ot-sandbox/docs/solution_walkthrough.md) | Step-by-step instructor/student solution manual for all exercise phases, tunneling commands, and flag extractions |
| 📊 [**Demo & Presentation Cheat-Sheet**](file:///opt/cyber-range/smartgrid-ot-sandbox/docs/demo_presentation_cheatsheet.md) | Presentation reference guide, high-level pitch, trade-offs, real-world cyberattack storytelling, and live demo checklist |

---

## ⚡ Quick Architecture Overview

```text
+---------------------------------------------------------------------------------------------------------+
| Level 4: Enterprise Analytics Network (10.0.1.0/24)                                                     |
|   - enterprise-host (10.0.1.10) - Enterprise Analytics, SAP/ERP & Management Reporting                |
+---------------------------------------------------------------------------------------------------------+
                                                  |
                                       [ purdue-gateway ] (Router)
                                                  |
+---------------------------------------------------------------------------------------------------------+
| Level 3.5: Industrial DMZ (IDMZ) (10.0.50.0/24)                                                         |
|   - idmz-jump (10.0.50.50) - Secure Jump Host with SSH / Bastion Isolation                              |
+---------------------------------------------------------------------------------------------------------+
                                                  |
                                       [ purdue-gateway ] (Router)
                                                  |
+---------------------------------------------------------------------------------------------------------+
| Level 3: SCADA Control Room Network (10.0.2.0/24)                                                       |
|   - scada-hmi (10.0.2.10) - Node-RED HMI + InfluxDB + Grafana Monitoring Dashboards                      |
|   - engineering-station (10.0.2.20) - OpenPLC Editor / Substation Configuration                        |
+---------------------------------------------------------------------------------------------------------+
                                                  |
                                       [ purdue-gateway ] (Router)
                                                  |
+---------------------------------------------------------------------------------------------------------+
| Level 2/1: Substation PLC Network (10.0.3.0/24)                                                         |
|   - substation-plc1 (10.0.3.10) - OpenPLC V3 Primary Substation Runtime (Modbus TCP Port 502)          |
|   - substation-plc2 (10.0.3.11) - OpenPLC V3 Secondary/Backup Substation Runtime                        |
+---------------------------------------------------------------------------------------------------------+
                                                  |
                                       [ purdue-gateway ] (Router)
                                                  |
+---------------------------------------------------------------------------------------------------------+
| Level 0: Physics Engine Network (10.0.4.0/24)                                                           |
|   - gridlabd-physics (10.0.4.10)                                                                        |
|     * GridLAB-D Physics Engine (IEEE 13-node Feeder GLM Model)                                         |
|     * Python Co-Simulation Bridge Service (`gridlabd_bridge.py` pymodbus + requests)                    |
+---------------------------------------------------------------------------------------------------------+
                                                  |
+---------------------------------------------------------------------------------------------------------+
| Corporate / Attacker Management Network (10.0.100.0/24)                                                |
|   - attacker-host (10.0.100.50) - Kali Linux Workstation with OT Penetration Testing Tools             |
+---------------------------------------------------------------------------------------------------------+
```
