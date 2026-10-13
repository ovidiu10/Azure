output "private_link_service_id" {
  description = "Resource ID to pass to the consumer stack."
  value       = azurerm_private_link_service.direct_connect.id
}

output "private_link_service_alias" {
  description = "Globally unique alias of the Private Link Service."
  value       = azurerm_private_link_service.direct_connect.alias
}

output "application_gateway_private_ip" {
  description = "Static PLS Direct Connect destination IP."
  value       = "10.10.1.10"
}

output "provider_resource_group_name" {
  description = "Provider resource group containing the PLS."
  value       = azurerm_resource_group.provider.name
}

output "vmss_egress_public_ip" {
  description = "Provider NAT Gateway public IP used only for outbound package and source retrieval."
  value       = azurerm_public_ip.egress.ip_address
}
