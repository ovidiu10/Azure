output "private_endpoint_ip" {
  description = "Consumer-side private IP used to reach the provider application."
  value       = "10.21.1.10"
}

output "application_fqdn" {
  description = "Private application hostname resolvable from both consumer VNets."
  value       = "app.plsdc.internal"
}

output "private_service_connection_name" {
  description = "Name of the cross-tenant private service connection."
  value       = "connection-to-provider-plsdc"
}

output "consumer_internal_load_balancer_ip" {
  description = "Static frontend IP of the consumer internal load balancer."
  value       = azurerm_lb.consumer.private_ip_address
}

output "vmss_egress_public_ip" {
  description = "Consumer NAT Gateway public IP used only for outbound package and source retrieval."
  value       = azurerm_public_ip.egress.ip_address
}

output "sockperf_private_link_test_command" {
  description = "Run from a consumer VMSS instance after the private endpoint connection is approved."
  value       = "sockperf ping-pong -i 10.21.1.10 --tcp -m 350 -t 101 -p 12345 --full-rtt"
}
