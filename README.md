# CyberRangeCZ Platform Lite

This guide aims to make the deployment of the CyberRangeCZ Platform as simple as possible for the evaluation and creation of CyberRangeCZ Platform content. For production workloads, standard deployment with external OpenStack deployment is recommended due to limited resources on a single host and slow performance of double to triple virtualization used by this guide.

The following steps will deploy OpenStack into a single KVM VM and set up CyberRangeCZ Platform inside the OpenStack instance.

Requirements:

* Ubuntu 24.04
* 8 VCPU, 48 GB RAM, 250 GB HDD (4 VCPU, 48 GB RAM is minimum for basic functionality)
* Platforms:
  * physical server
  * desktop
  * VM with nested virtualization enabled
  * cloud flavors with virtualization support - CyberRangeCZ Platform Lite works well with Google Cloud Platform instances **n2-highmem-4** and **n2-highmem-8**. You can use sample [Terraform](tf-gcp-vm) code to deploy a virtual machine for CyberRangeCZ Platform Lite to the Google Cloud Platform

## Deployment

```text
sudo apt install -y qemu-kvm libvirt-daemon libvirt-clients bridge-utils virt-manager docker.io
docker run -it --rm \
  -e LIBVIRT_DEFAULT_URI \
  -v /var/run/libvirt/:/var/run/libvirt/ \
  -v ~/.vagrant.d:/.vagrant.d \
  -v $(realpath "${PWD}"):${PWD} \
  -w "${PWD}" \
  --network host \
  vagrantlibvirt/vagrant-libvirt:latest \
  vagrant up
```

The URL of the CyberRangeCZ Platform portal is shown at the end of the provisioning.

### How to Access the Services from your Local Machine

Depending on your setup, you can access OpenStack Horizon (at `<http://10.1.2.9>`) and the CyberRange Portal (at `<https://<cluster_ip>/>`) using one of these options:

#### Option A: Local Deployment (VM runs on your local machine)

Because the `10.1.2.0/24` subnet is automatically bridged to your local machine, you can navigate directly to the IPs in your browser. No additional tunneling is required.

#### Option B: Remote Deployment (VM runs on a remote server/cloud VM)

If you run the Vagrant instance on a remote host, you must route the `10.1.2.0/24` subnet to your local machine:

* **Using `sshuttle` (Recommended):**

  ```bash
  sshuttle -r root@<remote-host-ip> 10.1.2.0/24
  ```

* **Using SSH Port Forwarding:**

  If you cannot use `sshuttle`, forward the specific ports:

```bash
  # For OpenStack Horizon
  ssh -L 8080:10.1.2.9:80 -N root@<remote-host-ip>

  # For CyberRange Portal
  ssh -L 8443:<cluster_ip>:443 -N root@<remote-host-ip>
  ```

*(Note: Remote access to the Portal via simple port-forwarding might experience redirection issues with Keycloak. `sshuttle` is strongly recommended.)*

## Additional information

OpenStack API & GUI is running on IP **10.1.2.9**

### OpenStack CLI access

OpenStack CLI is available inside VM. Execute:

`vagrant ssh -- -t 'sudo su'`

and you can start using CLI commands (RC file with credentials is already sourced).

### OpenStack GUI access

To access the Horizon portal, enter <http://10.1.2.9> into the browser. Login is admin.
Password can be retrieved from VM with command:

`grep "OS_PASSWORD" /etc/kolla/admin-openrc.sh`

### KVM environment

The installation will create VM with IP **10.1.2.10**.

The installation will create a 10.1.2.0/24 bridged network that is fully accessible from the host running the KVM instance.
