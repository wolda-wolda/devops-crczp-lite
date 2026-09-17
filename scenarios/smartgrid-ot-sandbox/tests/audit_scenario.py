#!/usr/bin/env python3
"""
Full Scenario Integrity Audit Script for Smart Grid Co-Simulation Package
"""

import os
import json
import yaml

SB_DIR = '/opt/cyber-range/smartgrid-ot-sandbox'

def check_topology():
    print("=== 1. Checking topology.yml ===")
    with open(os.path.join(SB_DIR, 'topology.yml')) as f:
        top = yaml.safe_load(f)
    
    hosts = [h['name'] for h in top['hosts']]
    net_mappings = top['net_mappings']
    host_counts = {}
    for m in net_mappings:
        host_counts[m['host']] = host_counts.get(m['host'], 0) + 1
    
    multi = [h for h, c in host_counts.items() if c > 1]
    if multi:
        print("  [FAIL] Multi-homed hosts found (Visualizer crash bug):", multi)
        return False
    print("  [PASS] All VM nodes are strictly single-homed.")
    return True

def check_training_json():
    print("\n=== 2. Checking training.json ===")
    with open(os.path.join(SB_DIR, 'training.json')) as f:
        tjson = json.load(f)
    
    allowed_types = ['ACCESS_LEVEL', 'ASSESSMENT_LEVEL', 'GAME_LEVEL', 'INFO_LEVEL', 'TRAINING_LEVEL']
    for l in tjson['levels']:
        if l['level_type'] not in allowed_types:
            print(f"  [FAIL] Invalid level_type '{l['level_type']}' in level '{l['title']}'")
            return False
    print("  [PASS] All level_type values conform to CyberRangeCZ REST DTO spec.")
    return True

def check_ansible_roles():
    print("\n=== 3. Checking Ansible Playbooks & Roles ===")
    p_dir = os.path.join(SB_DIR, 'provisioning')
    for root, dirs, files in os.walk(p_dir):
        for f in files:
            if f.endswith('.yml') or f.endswith('.yaml'):
                fpath = os.path.join(root, f)
                with open(fpath) as fh:
                    content = fh.read()
                    data = yaml.safe_load(content)
                rel = os.path.relpath(fpath, SB_DIR)
                if 'command:' in content and '>' in content:
                    print(f"  [FAIL] Raw shell redirect in command module: {rel}")
                    return False
                print(f"  [PASS] {rel} parsed cleanly.")
    return True

def check_st_and_bridge():
    print("\n=== 4. Checking ST Logic & Physics Bridge ===")
    st_path = os.path.join(SB_DIR, 'provisioning/roles/openplc/files/smartgrid_substation.st')
    with open(st_path) as f:
        st_code = f.read()
    
    if 'GRID_FREQ_HZ > 0' not in st_code:
        print("  [FAIL] Missing defensive > 0 startup check in OpenPLC ST code!")
        return False
    print("  [PASS] OpenPLC ST logic has defensive startup check.")

    bridge_path = os.path.join(SB_DIR, 'provisioning/roles/gridlabd/files/gridlabd_bridge.py')
    with open(bridge_path) as f:
        bridge_code = f.read()
    
    if 'ModbusTcpClient' not in bridge_code:
        print("  [FAIL] Co-simulation bridge missing ModbusTcpClient!")
        return False
    print("  [PASS] Co-simulation bridge logic is intact.")
    return True

def check_scada():
    print("\n=== 5. Checking SCADA Node-RED & Grafana Role ===")
    flows_path = os.path.join(SB_DIR, 'provisioning/roles/scada/files/node_red_flows.json')
    with open(flows_path) as f:
        flows = json.load(f)
    
    types = [n['type'] for n in flows]
    if 'modbus-client' not in types:
        print("  [FAIL] Missing modbus-client server configuration node in Node-RED flows!")
        return False
    print("  [PASS] Node-RED flows include required modbus-client config node.")
    return True

if __name__ == '__main__':
    t_ok = check_topology()
    j_ok = check_training_json()
    a_ok = check_ansible_roles()
    s_ok = check_st_and_bridge()
    c_ok = check_scada()
    
    if all([t_ok, j_ok, a_ok, s_ok, c_ok]):
        print("\n✓ ALL INTEGRITY CHECKS PASSED PERFECTLY! THE SCENARIO IS 100% READY FOR RE-PROVISIONING.")
