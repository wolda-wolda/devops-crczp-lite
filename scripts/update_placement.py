import urllib.request
import json
import subprocess

# 1. Get Token
token_cmd = "source /etc/kolla/admin-openrc.sh && source /root/kolla-ansible-venv/bin/activate && openstack token issue -c id -f value"
token = subprocess.check_output(token_cmd, shell=True, executable='/bin/bash').decode().strip()

uuid = "bb3c1ceb-12d9-4c4a-842a-07bde0d02492"
url = f"http://10.1.2.9:8780/resource_providers/{uuid}/inventories"

# 2. Get current inventories
req = urllib.request.Request(url, headers={"X-Auth-Token": token})
with urllib.request.urlopen(req) as response:
    data = json.loads(response.read().decode())

# 3. Update disk allocation ratio to 3.0
data['inventories']['DISK_GB']['allocation_ratio'] = 3.0

# 4. Perform PUT request
req_put = urllib.request.Request(
    url,
    data=json.dumps(data).encode(),
    headers={"X-Auth-Token": token, "Content-Type": "application/json"},
    method="PUT"
)
try:
    with urllib.request.urlopen(req_put) as response:
        print("Success:", response.read().decode())
except Exception as e:
    print("Error:", e.read().decode() if hasattr(e, 'read') else str(e))
