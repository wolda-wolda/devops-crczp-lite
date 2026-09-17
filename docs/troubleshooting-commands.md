# CyberRangeCZ Platform Command & Troubleshooting Reference

This document compiles the commands used for managing, debugging, and cleaning
up the local CyberRangeCZ platform.

---

## 1. Vagrant / Host-Level Commands

These commands are run on the host machine in the
`/opt/cyber-range/devops-crczp-lite` directory.

### Check VM Status

```bash
vagrant status
```

### SSH into the Parent VM

```bash
vagrant ssh
```

### Run Commands Inside the VM from Host

```bash
vagrant ssh -c "<command>"
```

*Example:*

```bash
vagrant ssh -c "sudo kubectl get pods -n crczp"
```

---

## 2. Kubernetes (k3s) Commands

Run these inside the Vagrant VM (or prefix with `vagrant ssh -c "..."` on the
host).

### List Pods in All Namespaces

```bash
sudo kubectl get pods -A
```

### List Pods in the `crczp` Namespace

```bash
sudo kubectl get pods -n crczp
```

### View Logs of a Microservice

```bash
sudo kubectl logs -n crczp deployment/sandbox-service --tail=100 -f
```

### Exec Into a Pod (e.g. sandbox-service)

```bash
sudo kubectl exec -it -n crczp deployment/sandbox-service -- /bin/bash
```

### Restart a Microservice Deployment

```bash
sudo kubectl rollout restart deployment/sandbox-service -n crczp
```

### Check Rollout Status of a Microservice

```bash
sudo kubectl rollout status deployment/sandbox-service -n crczp
```

### Get Kubernetes Secrets

```bash
sudo kubectl get secrets -n crczp
```

### Extract/View a Secret Value (e.g., config.yml)

```bash
sudo kubectl get secret sandbox-service-secret -n crczp -o jsonpath='{.data.config\.yml}' | base64 -d
```

### Get ConfigMap Contents

```bash
sudo kubectl get configmap training-service-configmap -n crczp -o yaml
```

---

## 3. OpenStack CLI Commands

To run OpenStack CLI commands, you must first source the admin configuration and
activate the Kolla Ansible python virtual environment in the Vagrant VM.

### Standard Setup Script

Run this inside the Vagrant VM to prepare the environment:

```bash
source /etc/kolla/admin-openrc.sh
source /root/kolla-ansible-venv/bin/activate
```

### List Virtual Machine Instances

```bash
openstack server list --all
```

### List Networks & Identify Orphaned Networks

```bash
openstack network list
```

### Delete Stuck/Orphaned Network

If a sandbox deletion fails, it may leave network resources behind. Delete them
manually:

```bash
openstack network delete <network-id-or-name>
```

### List Routers & Ports

```bash
openstack router list
openstack port list
```

---

## 4. PostgreSQL Database Queries

CyberRangeCZ databases are managed via CloudNative-PG (`cnpg`) in Kubernetes. The
database cluster is accessible at
`postgres-rw.cnpg-system.svc.cluster.local:5432`.

### List Databases

```bash
sudo kubectl exec -n cnpg-system postgres-1 -- psql -U postgres -l
```

### List Tables in a Database

*For sandbox-service:*

```bash
sudo kubectl exec -n cnpg-system postgres-1 -- psql -U postgres -d sandbox-service -c '\dt'
```

*For training-service:*

```bash
sudo kubectl exec -n cnpg-system postgres-1 -- psql -U postgres -d training -c '\dt'
```

### Query Rows in a Table

```bash
sudo kubectl exec -n cnpg-system postgres-1 -- psql -U postgres -d sandbox-service -c 'select id, name, url, rev from sandbox_definition_app_definition;'
```

---

## 5. Django DB Cleanup (Django Shell)

When the UI gets stuck due to failed Git pulls or Terraform allocations, you can
force-delete definitions or pools from the database using the Django interactive
shell inside the `sandbox-service` container.

### Run Django Commands Direct

Run a one-liner command using `python /app/manage.py shell -c`:

```bash
sudo kubectl exec -n crczp deployment/sandbox-service -- python /app/manage.py shell -c '
from crczp.sandbox_instance_app.models import Pool
from crczp.sandbox_definition_app.models import Definition

# List all Definitions and Pools

print("POOLS:", [(p.id, p.size) for p in Pool.objects.all()])
print("DEFINITIONS:", [(d.id, d.name) for d in Definition.objects.all()])
'
```

### Force Delete a Stuck Pool or Definition

If a pool or definition is stuck in "deleting" or "failed" status:

```bash
sudo kubectl exec -n crczp deployment/sandbox-service -- python /app/manage.py shell -c '
from crczp.sandbox_instance_app.models import Pool
from crczp.sandbox_definition_app.models import Definition

# Deleting Pool 5

Pool.objects.filter(id=5).delete()

# Deleting Definition 2

Definition.objects.filter(id=2).delete()
'
```

*Note: Due to Django's cascading deletes, deleting a Pool will automatically
clean up all dependent Sandboxes, SandboxAllocationUnits, and Stages.*

---

## 6. Access Credentials

* **CyberRange Portal GUI**: `<<https://10.1.2.175/`>>
  * Username: `crczp-admin`
  * Password: `password` (User is named `Demo Admin` in Keycloak)
* **Grafana Dashboard**: `<<https://10.1.2.175/grafana/`>>
  * Username/Password are fetched from Keycloak client secrets.
* **Headlamp (Kubernetes Dashboard)**: `<<https://10.1.2.175/headlamp/`>>
  * Authentication: Requires a bearer token. Generate it from the host using:

    ```bash
    vagrant ssh -c "sudo kubectl create token my-headlamp -n kube-system"
    ```

---

## 7. Deploying & Exposing Headlamp (Kubernetes Dashboard) Manually

Since Headlamp is self-deployed, you can recreate, upgrade, or configure the
installation using the following commands:

### Step A: Add the Helm Repository (inside the Vagrant VM)

```bash
vagrant ssh -c "sudo helm repo add headlamp <<https://kubernetes-sigs.github.io/headlamp>>/"
vagrant ssh -c "sudo helm repo update"
```

### Step B: Install/Upgrade the Release with Traefik Ingress

To configure Headlamp to run under the `/headlamp` prefix and expose it through
Traefik, run:

```bash
vagrant ssh -c "sudo helm upgrade --install my-headlamp headlamp/headlamp \
  -n kube-system \
  --set config.baseURL=/headlamp \
  --set ingress.enabled=true \
  --set ingress.ingressClassName=traefik \
  --set 'ingress.hosts[0].paths[0].path=/headlamp' \
  --set 'ingress.hosts[0].paths[0].type=Prefix'"
```

### Step C: Handle Trailing Slash Redirection (Optional but Recommended)

By default, Headlamp expects requests to include a trailing slash (e.g.
`/headlamp/`). To make `/headlamp` automatically redirect to `/headlamp/`
(preventing a 404 error), configure a Traefik RedirectRegex middleware and
annotate the Ingress:

1. **Create the Middleware resource:**

   ```bash
   vagrant ssh -c "cat <<'EOF' | sudo kubectl apply -f -
   apiVersion: traefik.io/v1alpha1
   kind: Middleware
   metadata:
     name: headlamp-redirect
     namespace: kube-system
   spec:
     redirectRegex:
       regex: '^(https?://[^/]+)/headlamp$'
       replacement: '\${1}/headlamp/'
       permanent: true
   EOF"
   ```

2. **Annotate the Ingress:**

```bash
   vagrant ssh -c "sudo kubectl annotate ingress my-headlamp -n kube-system \"traefik.ingress.kubernetes.io/router.middlewares=kube-system-headlamp-redirect@kubernetescrd\" --overwrite"
   ```

### Step D: Generate Login Token

```bash
vagrant ssh -c "sudo kubectl create token my-headlamp -n kube-system"
```

---

## 8. OpenStack Resource Limit/Scheduler Troubleshooting

If a sandbox VM deployment fails during allocation with:
`Error waiting for instance to become ready: unexpected state 'ERROR', wanted target 'ACTIVE'`

This is usually caused by Nova scheduler failing to allocate the requested resources (disk, RAM, or vCPUs).

### Step A: Identify the scheduling fault
Run this inside the Vagrant VM to find the failed VM UUID and its exact scheduler reason:
```bash
# Sourced env required:
source /etc/kolla/admin-openrc.sh
source /root/kolla-ansible-venv/bin/activate

# Look for scheduling errors:
sudo grep -rn 'Setting instance to ERROR state' /var/log/kolla/nova/
```
If you see: `nova.exception_Remote.NoValidHost_Remote: No valid host was found`, it means the requested resources exceed OpenStack's free scheduling capacity.

### Step B: Check OpenStack Resource Usages and Limits
```bash
# Check absolute project quotas
openstack limits show --absolute

# Query active resource provider usages & allocation ratios via Placement API
TOKEN=$(openstack token issue -c id -f value)
UUID="bb3c1ceb-12d9-4c4a-842a-07bde0d02492"
curl -s -H "X-Auth-Token: $TOKEN" http://10.1.2.9:8780/resource_providers/$UUID/usages
curl -s -H "X-Auth-Token: $TOKEN" http://10.1.2.9:8780/resource_providers/$UUID/inventories
```

### Step C: Increase Disk Allocation Overcommit Ratio
By default, the disk allocation ratio is `1.0`. In a nested virtual range where files use Copy-on-Write (`qcow2`), we can safely overcommit virtual disk limits to allow concurrent sandbox runs:

1. **Inject `disk_allocation_ratio = 3.0` override:**
   ```bash
   sudo find /etc/kolla/ -name 'nova.conf' -exec sed -i '/^\[DEFAULT\]/a disk_allocation_ratio = 3.0' {} \;
   ```
2. **Restart Nova Services:**
   ```bash
   sudo docker restart nova_compute nova_scheduler nova_api nova_conductor
   ```
3. **Execute Python Override Helper to update active Placement records immediately:**
   ```bash
   sudo python3 /vagrant/scripts/update_placement.py
   ```
