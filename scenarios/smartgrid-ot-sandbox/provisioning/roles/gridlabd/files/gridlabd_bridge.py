#!/usr/bin/env python3
"""
Smart Grid Co-Simulation Bridge
Interfaces GridLAB-D IEEE 13-node physics simulation with OpenPLC Substation Modbus TCP Runtime.
"""

import time
import sys
import logging
import requests
try:
    from pymodbus.client import ModbusTcpClient
except ImportError:
    try:
        from pymodbus.client.sync import ModbusTcpClient
    except ImportError:
        from pymodbus.client.tcp import ModbusTcpClient


# Configure logging
logging.basicConfig(
    filename='/var/log/gridlabd_bridge.log',
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
console = logging.StreamHandler()
console.setLevel(logging.INFO)
logging.getLogger('').addHandler(console)

PLC_IP = "10.0.3.10"
PLC_PORT = 502
INFLUXDB_URL = "http://10.0.2.10:8086/write?db=smartgrid"
POLL_INTERVAL = 1.0

# Base Physics Simulation State
sim_state = {
    "voltage_v": 240.0,
    "load_kw": 1500,
    "tap_pos": 0,
    "freq_hz": 60.00,
    "breaker_closed": True,
    "cap_bank_on": True,
    "flag_triggered": False
}

def send_influx_telemetry():
    try:
        breaker_val = 1 if sim_state["breaker_closed"] else 0
        payload = f"substation_telemetry voltage={sim_state['voltage_v']},breaker_closed={breaker_val},freq={sim_state['freq_hz']}"
        requests.post(INFLUXDB_URL, data=payload, timeout=2)
    except Exception:
        pass

def main():
    logging.info("Starting GridLAB-D Co-Simulation Bridge...")
    logging.info(f"Targeting Substation OpenPLC at {PLC_IP}:{PLC_PORT}")

    while True:
        try:
            client = ModbusTcpClient(PLC_IP, port=PLC_PORT, timeout=3)
            if not client.connect():
                logging.warning(f"Unable to connect to OpenPLC at {PLC_IP}:{PLC_PORT}. Retrying...")
                time.sleep(POLL_INTERVAL)
                continue

            logging.info("Connected to OpenPLC. Setting initial breaker status to Closed (True)...")
            client.write_coil(0, True)

            logging.info("Starting Co-Simulation Loop...")

            while True:
                # 1. Read Coils from OpenPLC (Coil 0 = Breaker, Coil 1 = Cap Bank)
                rr_coils = client.read_coils(0, count=2)
                if not rr_coils.isError():
                    sim_state["breaker_closed"] = rr_coils.bits[0]
                    sim_state["cap_bank_on"] = rr_coils.bits[1]

                # 2. Read Holding Registers (Register 2 = Tap Changer Position set by OpenPLC)
                rr_regs = client.read_holding_registers(0, count=4)
                if not rr_regs.isError():
                    sim_state["tap_pos"] = rr_regs.registers[2]

                # 3. Simulate Physics Reaction
                if not sim_state["breaker_closed"]:
                    # Circuit Breaker Tripped! Physical Grid Collapse
                    sim_state["voltage_v"] = 0.0
                    sim_state["load_kw"] = 0
                    sim_state["freq_hz"] = 0.00
                    if not sim_state["flag_triggered"]:
                        logging.critical("PHYSICAL IMPACT DETECTED: Main Feeder Circuit Breaker Tripped!")
                        logging.critical("FLAG{GRID_PHYSICAL_COLLAPSE_SUCCESSFUL}")
                        sim_state["flag_triggered"] = True
                else:
                    # Normal Operation dynamics with Tap Position adjustment
                    base_v = 240.0 + (sim_state["tap_pos"] * 0.625)
                    if sim_state["cap_bank_on"]:
                        base_v += 2.5
                    sim_state["voltage_v"] = max(180.0, min(300.0, base_v))
                    sim_state["load_kw"] = 1500
                    sim_state["freq_hz"] = 60.00

                # 4. Write physics feedback telemetry to OpenPLC Holding Registers
                v_scaled = int(sim_state["voltage_v"] * 10)
                freq_scaled = int(sim_state["freq_hz"] * 100)
                
                client.write_register(0, v_scaled)
                client.write_register(1, sim_state["load_kw"])
                client.write_register(3, freq_scaled)

                # 5. Push telemetry to InfluxDB for Grafana Visualization
                send_influx_telemetry()

                time.sleep(POLL_INTERVAL)

        except Exception as e:
            logging.error(f"Error in bridge execution loop: {e}")
            time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
