# tf-gcp-vm

Code for deploying virtual machine, which is able to host CyberRangeCZ Platform
lite. Steps:

1. Log in to https://console.cloud.google.com
2. Create CyberRangeCZ Platform lite project
3. https://console.cloud.google.com/iam-admin/serviceaccounts - manage keys on
   "Compute Engine default service account" - create a new key
4. Rename created JSON file to auth.json and move it to tf-gcp-vm directory
5. `terraform init`
6. `terraform apply`
7. `terraform output -raw tls_private_key > gcp.key && chmod 600 gcp.key`
8. ``ssh -i gcp.key ubuntu@`terraform output -raw public_ip_address` ``
