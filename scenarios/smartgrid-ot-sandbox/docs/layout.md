# Operation Blackout Zero - Architecture & Network Layout

## System Overview

**Operation Blackout Zero** is a 100% software-emulated Smart Grid Co-Simulation Cyber Range package designed for CyberRangeCZ (KYPO CRP) running on OpenStack Heat. It emulates a multi-tier electric utility network structured according to the **Purdue Enterprise Reference Architecture (PERA)** and **ISA/IEC 62443** industrial network security standards.

The package couples a Level 0 physics engine (**GridLAB-D IEEE 13-Node Test Feeder**) with Level 1 Substation logic (**OpenPLC V3**), Level 3 SCADA Control Room monitoring (**Node-RED**, **InfluxDB**, **Grafana**), and an Industrial DMZ (**IDMZ Jump Host**) via a high-performance Python 3 co-simulation bridge (`gridlabd_bridge.py`).

---

## Purdue Model Network Map & Subnets

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

---

## Detailed Node & IP Address Allocations

| Node Name | Purdue Level | Base Image | OpenStack Flavor | IP Address | Primary Services |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `attacker-host` | Mgmt | `kali` | `kali` | `10.0.100.50` | Nmap, Hydra, Python pymodbus, `modbus_attack.py` |
| `purdue-gateway` | Router | `debian-12-x86_64` | `ot.router` | Multi-homed | IPv4 Router, iptables Purdue Firewall |
| `idmz-jump` | IDMZ (L3.5) | `debian-12-x86_64` | `ot.jump` | `10.0.50.50` | OpenSSH Bastion Server |
| `enterprise-host` | Level 4 | `debian-12-x86_64` | `ot.hmi` | `10.0.1.10` | Enterprise Analytics & Web Reporting |
| `scada-hmi` | Level 3 | `debian-12-x86_64` | `ot.hmi` | `10.0.2.10` | Node-RED (1880), InfluxDB (8086), Grafana (3000) |
| `engineering-station`| Level 3 | `debian-12-x86_64` | `ot.ews` | `10.0.2.20` | OpenPLC Editor, Substation ST compiler |
| `substation-plc1` | Level 2/1 | `debian-12-x86_64` | `ot.plc` | `10.0.3.10` | OpenPLC V3 Modbus TCP Runtime (Port 502) |
| `substation-plc2` | Level 2/1 | `debian-12-x86_64` | `ot.plc` | `10.0.3.11` | OpenPLC V3 Secondary Substation |
| `gridlabd-physics` | Level 0 | `debian-12-x86_64` | `ot.plc` | `10.0.4.10` | GridLAB-D IEEE 13-node, `gridlabd_bridge.py` |

---

## Modbus TCP Register Mapping Protocol

The communication between **OpenPLC Substation**, **GridLAB-D Co-Simulation Bridge**, and **Node-RED SCADA** relies on standard Modbus TCP (Port 502):

| Register Type | Modbus Addr | ST Signal Name | Unit / Range | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Coil (0x)** | `00001` (0) | `CB_MAIN_CLOSED` | BOOL (`0` or `1`) | Main Substation Feeder Circuit Breaker |
| **Coil (0x)** | `00002` (1) | `CAP_BANK_ENABLED` | BOOL (`0` or `1`) | Substation Capacitor Bank Relay |
| **Coil (0x)** | `00003` (2) | `ALARM_OVERVOLTAGE` | BOOL (`0` or `1`) | Substation Over-voltage Trip Alarm |
| **Discrete Input (1x)**| `10001` (0) | `GRID_HEALTH_OK` | BOOL (`0` or `1`) | Grid Stability Indicator |
| **Holding Reg (4x)** | `40001` (0) | `BUS632_VOLTAGE_V` | UINT16 (Scaled x10) | Bus 632 RMS Voltage (e.g. 2400 = 240.0V) |
| **Holding Reg (4x)** | `40002` (1) | `FEEDER_LOAD_KW` | UINT16 (kW) | Substation Feeder Active Power Load |
| **Holding Reg (4x)** | `40003` (2) | `TAP_CHANGER_POS` | INT16 (-16 to +16) | Transformer Regulator Tap Changer Position |
| **Holding Reg (4x)** | `40004` (3) | `GRID_FREQ_HZ` | UINT16 (Scaled x100) | Grid Frequency (e.g. 6000 = 60.00 Hz) |

---

## Firewall Rules & Zone Segregation Policy

`purdue-gateway` enforces strict Purdue zone boundary controls via `iptables`:
- **Mgmt (`10.0.100.0/24`) → IDMZ (`10.0.50.0/24`)**: ACCEPT (SSH)
- **IDMZ (`10.0.50.0/24`) → SCADA (`10.0.2.0/24`)**: ACCEPT (SSH / HTTP)
- **SCADA (`10.0.2.0/24`) → Substation (`10.0.3.0/24`)**: ACCEPT (Modbus TCP 502)
- **Substation (`10.0.3.0/24`) → Physics (`10.0.4.0/24`)**: ACCEPT (Co-simulation Telemetry)
- **Physics (`10.0.4.0/24`) → Substation (`10.0.3.0/24`)**: ACCEPT (Modbus TCP return path)
- **Physics (`10.0.4.0/24`) → SCADA (`10.0.2.0/24`)**: ACCEPT (InfluxDB telemetry POST)
- **Direct Corporate/Mgmt → Physics Engine**: **DROP** (Enforces Purdue isolation)
