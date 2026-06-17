# -*- mode: ruby -*-

# vi: set ft=ruby :

require 'etc'

def detect_default_cpu
  host_cpus = Etc.nprocessors rescue 8
  if host_cpus > 8
    host_cpus - 4  # Leave 4 cores for host overhead
  elsif host_cpus > 4
    host_cpus - 2
  else
    host_cpus
  end
end

def detect_default_ram
  if File.exist?("/proc/meminfo")
    mem_total_kb = File.read("/proc/meminfo")[/MemTotal:\s+(\d+)\s+kB/, 1]
    if mem_total_kb
      host_ram_mb = mem_total_kb.to_i / 1024
      # Leave 8GB for host if we have more than 16GB to prevent swapping, else leave 4GB
      if host_ram_mb > 16384
        return host_ram_mb - 8192
      elsif host_ram_mb > 8192
        return host_ram_mb - 4096
      else
        return host_ram_mb
      end
    end
  end
  45056 # fallback
end

dns1 = ENV["DNS1"] || "1.1.1.1"
dns2 = ENV["DNS2"] || "1.0.0.1"
cpu = ENV["CPU"] ? ENV["CPU"].to_i : detect_default_cpu
ram = ENV["RAM"] ? ENV["RAM"].to_i : detect_default_ram

Vagrant.configure(2) do |config|

  config.vm.box = "bento/ubuntu-24.04"
  config.vm.box_version = "202508.03.0"
  config.vm.hostname = "openstack"

  config.vm.network :private_network,
    ip: "10.1.2.10"

  config.vm.network :private_network,
    ip: "10.1.2.11",
    auto_config: false

  config.vm.provider :libvirt do |libvirt|
    libvirt.cpus = cpu
    libvirt.memory = ram
    libvirt.nested = true
    libvirt.cpu_mode = 'host-passthrough'
    libvirt.disk_driver :cache => 'unsafe'
    libvirt.machine_virtual_size = 250
  end

  # File provisioning - copy configuration and scripts
  config.vm.provision "file",
    source: "ansible.cfg",
    destination: "/tmp/ansible.cfg",
    run: "once"

  config.vm.provision "file",
    source: "scripts/",
    destination: "/tmp/",
    run: "once"

  # Shared folder configuration
  config.vm.synced_folder ".", "/vagrant"

  # Phase 1: System Setup
  config.vm.provision "system-setup",
    type: "shell",
    name: "System Setup and Package Installation",
    env: {
      "DNS1" => dns1,
      "DNS2" => dns2,
      "RAM" => ram.to_s
    },
    path: "scripts/01-system-setup.sh",
    run: "once"

  # Phase 2: OpenStack Deployment
  config.vm.provision "openstack-deployment",
    type: "shell",
    name: "OpenStack Deployment with Kolla-Ansible",
    path: "scripts/02-openstack-deploy.sh",
    run: "once",
    privileged: true

  # Phase 3: Infrastructure Deployment
  config.vm.provision "infrastructure-deployment",
    type: "shell",
    name: "Kubernetes and Application Infrastructure",
    env: {
      "DNS1" => dns1,
      "DNS2" => dns2
    },
    path: "scripts/03-infrastructure-deploy.sh",
    run: "once",
    privileged: true

  # Phase 4: Final Setup
  config.vm.provision "final-setup",
    type: "shell",
    name: "Final Configuration and Information Display",
    path: "scripts/04-final-setup.sh",
    run: "once",
    privileged: true
end
