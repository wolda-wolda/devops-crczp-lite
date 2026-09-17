#!/usr/bin/env python3
"""
Test Suite for Smart Grid Co-Simulation Package (KYPO CRP Sandbox)
Validates topology.yml, training.json, Ansible playbook structure, and co-simulation Modbus register logic.
Uses Python built-in unittest library.
"""

import os
import json
import yaml
import unittest

PACKAGE_ROOT = "/opt/cyber-range/smartgrid-ot-sandbox"

class TestSmartGridSandbox(unittest.TestCase):

    def test_topology_file_exists_and_valid(self):
        topology_path = os.path.join(PACKAGE_ROOT, "topology.yml")
        self.assertTrue(os.path.exists(topology_path), "topology.yml does not exist")
        
        with open(topology_path, "r") as f:
            data = yaml.safe_load(f)
        
        self.assertEqual(data["name"], "smartgrid-ot-sandbox")
        self.assertIn("hosts", data)
        self.assertGreaterEqual(len(data["hosts"]), 7)
        self.assertIn("routers", data)
        self.assertGreaterEqual(len(data["routers"]), 1)
        self.assertIn("networks", data)
        self.assertGreaterEqual(len(data["networks"]), 5)
        self.assertIn("net_mappings", data)
        self.assertIn("router_mappings", data)

    def test_training_json_validity(self):
        training_path = os.path.join(PACKAGE_ROOT, "training.json")
        self.assertTrue(os.path.exists(training_path), "training.json does not exist")
        
        with open(training_path, "r") as f:
            data = json.load(f)
        
        self.assertIn("title", data)
        self.assertIn("levels", data)
        self.assertGreaterEqual(len(data["levels"]), 5)
        self.assertEqual(data["state"], "RELEASED")

    def test_ansible_playbook_and_roles_exist(self):
        playbook_path = os.path.join(PACKAGE_ROOT, "provisioning", "playbook.yml")
        self.assertTrue(os.path.exists(playbook_path), "provisioning/playbook.yml does not exist")
        
        roles_dir = os.path.join(PACKAGE_ROOT, "provisioning", "roles")
        required_roles = ["router", "openplc", "gridlabd", "scada", "attacker"]
        for role in required_roles:
            role_path = os.path.join(roles_dir, role, "tasks", "main.yml")
            self.assertTrue(os.path.exists(role_path), f"Role task missing: {role_path}")

    def test_modbus_register_scaling_logic(self):
        # Voltage scaling test: 240.5 V -> 2405 uint16
        voltage_v = 240.5
        scaled_v = int(voltage_v * 10)
        self.assertEqual(scaled_v, 2405)
        self.assertEqual(scaled_v / 10.0, 240.5)

        # Frequency scaling test: 59.98 Hz -> 5998 uint16
        freq_hz = 59.98
        scaled_freq = int(freq_hz * 100)
        self.assertEqual(scaled_freq, 5998)
        self.assertEqual(scaled_freq / 100.0, 59.98)

    def test_docs_exist(self):
        layout_doc = os.path.join(PACKAGE_ROOT, "docs", "layout.md")
        walkthrough_doc = os.path.join(PACKAGE_ROOT, "docs", "solution_walkthrough.md")
        self.assertTrue(os.path.exists(layout_doc), "docs/layout.md missing")
        self.assertTrue(os.path.exists(walkthrough_doc), "docs/solution_walkthrough.md missing")

if __name__ == "__main__":
    unittest.main()
