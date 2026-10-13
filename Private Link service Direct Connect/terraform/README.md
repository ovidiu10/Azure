# Private Link Service Direct Connect

This Terraform deploys the cross-tenant architecture in the diagram in **East US 2**:

- `provider/`: private Application Gateway, two-instance backend VMSS, and a Private Link Service Direct Connect with two NAT IP configurations.
- `consumer/`: two peered VNets, a two-instance VMSS behind an internal load balancer, and a private endpoint to the provider PLS.

The stacks are intentionally separate because each tenant owns its own Terraform state and credentials. The provider must approve the consumer's private endpoint request.

Both VM scale sets use Ubuntu 24.04 LTS, `Standard_D2s_v5`, and Accelerated Networking. Cloud-init installs common network diagnostics plus Sockperf from the Mellanox repository. Each VMSS subnet has a NAT Gateway so package installation and the Sockperf source build do not depend on Azure default outbound access.

## Prerequisites

1. Terraform 1.6 or later and Azure CLI.
2. Contributor access in each target subscription.
3. Register the PLS Direct Connect preview feature in the provider subscription:

   ```powershell
   az login --tenant <provider-tenant-id>
   az account set --subscription <provider-subscription-id>
   az feature register --namespace Microsoft.Network --name AllowPrivateLinkserviceUDR
   az provider register --namespace Microsoft.Network
   az feature show --namespace Microsoft.Network --name AllowPrivateLinkserviceUDR --query properties.state -o tsv
   ```

   Wait until the feature state is `Registered`.

4. A PFX certificate for `app.plsdc.internal`. The Application Gateway terminates TLS and sends HTTP to the backend VMSS. For this lab, generate a private root CA and server certificate:

   ```powershell
   .\New-TestCertificate.ps1
   ```

   The script prompts for a PFX password and creates:

   - `certificates\app.plsdc.internal.pfx`
   - `certificates\app.plsdc.internal.pfx.base64`
   - `certificates\plsdc-lab-root-ca.crt`

   Put the Base64 file contents and the password you entered into `provider\terraform.tfvars`:

   ```hcl
   tls_certificate_pfx_base64 = "<contents of app.plsdc.internal.pfx.base64>"
   tls_certificate_password   = "<the PFX password>"
   ```

## Deploy

Copy each example variables file and replace its placeholders:

```powershell
Copy-Item .\provider\terraform.tfvars.example .\provider\terraform.tfvars
Copy-Item .\consumer\terraform.tfvars.example .\consumer\terraform.tfvars
```

Authenticate to the provider tenant and deploy:

```powershell
Set-Location .\provider
$env:ARM_TENANT_ID = "<provider-tenant-id>"
$env:ARM_SUBSCRIPTION_ID = "<provider-subscription-id>"
terraform init
terraform apply
terraform output -raw private_link_service_id
```

Set `private_link_service_id` in `consumer\terraform.tfvars`, then authenticate to the consumer tenant and deploy:

```powershell
Set-Location ..\consumer
$env:ARM_TENANT_ID = "<consumer-tenant-id>"
$env:ARM_SUBSCRIPTION_ID = "<consumer-subscription-id>"
terraform init
terraform apply
```

The provider owner then approves the pending connection:

```powershell
az login --tenant <provider-tenant-id>
az account set --subscription <provider-subscription-id>
$connectionId = az network private-link-service show `
  --resource-group rg-plsdc-provider `
  --name pls-appgw-direct-connect `
  --query "privateEndpointConnections[?properties.privateLinkServiceConnectionState.status=='Pending'].id | [0]" `
  -o tsv
az network private-endpoint-connection approve --id $connectionId --description "Approved"
```

From the consumer VMSS network, the application is available at `https://app.plsdc.internal`.

## Trust the HTTPS certificate on consumer Linux

The consumer must trust only the public root CA file, not the PFX or its private key. To install the generated CA on both consumer VMSS instances without SSH:

```powershell
$caBase64 = [Convert]::ToBase64String(
  [IO.File]::ReadAllBytes(".\certificates\plsdc-lab-root-ca.crt")
)

0..1 | ForEach-Object {
  az vmss run-command invoke `
    --resource-group rg-plsdc-consumer `
    --name vmss-consumer-client `
    --instance-id $_ `
    --command-id RunShellScript `
    --scripts "echo '$caBase64' | base64 -d | sudo tee /usr/local/share/ca-certificates/plsdc-lab-root-ca.crt >/dev/null && sudo update-ca-certificates"
}
```

Verify HTTPS trust from a consumer instance:

```powershell
az vmss run-command invoke `
  --resource-group rg-plsdc-consumer `
  --name vmss-consumer-client `
  --instance-id 0 `
  --command-id RunShellScript `
  --scripts "curl --fail --show-error https://app.plsdc.internal"
```

The provider VMSS does not need this CA because Application Gateway terminates HTTPS. SockPerf also does not use certificates because its test path uses raw TCP on port `12345`.

## SockPerf latency test

Port `12345/TCP` follows the complete private path:

`consumer VMSS → private endpoint 10.21.1.10 → PLS Direct Connect → Application Gateway 10.10.1.10 TCP listener → provider VMSS`

The provider cloud-init starts `sockperf sr` on port `12345` on both backend instances. The Application Gateway uses a TCP health probe and Layer 4 TCP proxy rule for that port. The provider NSG accepts the backend flow only from the Application Gateway subnet, and the consumer NSG allows the client flow only to the private endpoint IP.

After the private endpoint connection is approved, run the Microsoft-recommended TCP ping-pong test from a consumer VMSS instance:

```bash
sockperf ping-pong -i 10.21.1.10 --tcp -m 350 -t 101 -p 12345 --full-rtt
```

To invoke the test without direct SSH access:

```powershell
az vmss run-command invoke `
  --resource-group rg-plsdc-consumer `
  --name vmss-consumer-client `
  --instance-id 0 `
  --command-id RunShellScript `
  --scripts "sockperf ping-pong -i 10.21.1.10 --tcp -m 350 -t 101 -p 12345 --full-rtt"
```

This result includes Private Endpoint, PLS Direct Connect, Application Gateway TCP proxy, and provider VMSS processing latency. It is an end-to-end architecture measurement rather than isolated PLS latency.

## Notes

- PLS Direct Connect is a public-preview feature and currently requires the private endpoint, PLS, and client VM to be in the same supported region.
- The destination is the Application Gateway's static private frontend IP. A standard load balancer is not required on the provider side for Direct Connect.
- The PLS follows the Microsoft Terraform sample: `destination_ip_address` is static, the PLS subnet disables service network policies, and the service has two NAT IP configurations.
- The consumer uses `private_endpoint_network_policies = "Disabled"`. This is the current AzureRM 4.x schema; the similarly named Boolean attribute shown in the Microsoft sample is not accepted by current provider releases.
- `Standard_D2s_v5` is a common two-vCPU general-purpose size that supports Accelerated Networking. Override `vmss_sku` only with another size that supports Accelerated Networking in the target region.
- Installed tools include `ip`, `ss`, `ethtool`, `ifconfig`, `dig`, `traceroute`, `tcpdump`, `nmap`, `nc`, `iperf3`, `curl`, `jq`, and `sockperf`. The SockPerf source build includes the Ubuntu dependencies documented by Microsoft.
- Terraform state can contain infrastructure identifiers and certificate material. Use encrypted remote state with restricted access.
