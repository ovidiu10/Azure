output "resource_group_name" {
  description = "Resource group holding the PoC resources."
  value       = azurerm_resource_group.poc.name
}

output "adx_cluster_name" {
  description = "Azure Data Explorer cluster name."
  value       = azurerm_kusto_cluster.adx.name
}

output "adx_cluster_id" {
  description = "ADX cluster resource ID - needed by the approval script."
  value       = azurerm_kusto_cluster.adx.id
}

output "adx_cluster_uri" {
  description = "ADX cluster URI. Use this as the Grafana data source Cluster URL."
  value       = azurerm_kusto_cluster.adx.uri
}

output "adx_database_name" {
  description = "ADX database used as the Database Watcher data store."
  value       = azurerm_kusto_database.watcher.name
}

output "watcher_id" {
  description = "Database Watcher resource ID."
  value       = azapi_resource.watcher.id
}

output "watcher_name" {
  description = "Database Watcher name."
  value       = azapi_resource.watcher.name
}

output "watcher_principal_id" {
  description = "Object ID of the watcher managed identity. Use this in the T-SQL grant script on the SQL MI."
  value       = azapi_resource.watcher.output.identity.principalId
}

output "alert_rule_identity_id" {
  description = "Resource ID of the user-assigned identity used by Azure Monitor alert rules created from watcher templates."
  value       = var.create_alert_rule_identity ? azurerm_user_assigned_identity.alert_rules[0].id : null
}

output "jumpbox_public_ip" {
  description = "Public IP of the Phase 2 verification jumpbox, when one could be created."
  value       = var.create_jumpbox && var.jumpbox_public_ip ? azurerm_public_ip.jumpbox[0].ip_address : null
}

output "jumpbox_admin_username" {
  description = "Local administrator name on the jumpbox."
  value       = var.create_jumpbox ? var.jumpbox_admin_username : null
}

output "jumpbox_password" {
  description = "Generated jumpbox password. Read with: terraform output -raw jumpbox_password"
  value       = var.create_jumpbox ? random_password.jumpbox[0].result : null
  sensitive   = true
}

output "sqlmi_id" {
  description = "Resource ID of the monitored SQL MI - needed by the approval script."
  value       = data.azurerm_mssql_managed_instance.target.id
}

output "sqlmi_fqdn" {
  description = "FQDN of the monitored SQL MI."
  value       = data.azurerm_mssql_managed_instance.target.fqdn
}

output "grafana_name" {
  description = "Azure Managed Grafana workspace name."
  value       = azurerm_dashboard_grafana.amg.name
}

output "grafana_endpoint" {
  description = "Grafana URL. Reachable only from the private endpoint once lock_down_public_access = true."
  value       = azurerm_dashboard_grafana.amg.endpoint
}

output "grafana_principal_id" {
  description = "Object ID of the Grafana managed identity."
  value       = azurerm_dashboard_grafana.amg.identity[0].principal_id
}

output "grafana_outbound_ips" {
  description = "Deterministic outbound IPs - use these for SMTP relay or ITSM allow-lists."
  value       = azurerm_dashboard_grafana.amg.outbound_ip
}

output "next_steps" {
  description = "What to do after apply."
  value       = <<-EOT

    1. Approve the pending private endpoint connections:
         ./scripts/approve-private-endpoints.ps1

    2. Grant the watcher access on the SQL MI (T-SQL, run as an Entra admin):
         scripts/grant-watcher-on-sqlmi.sql
       Watcher identity object ID: ${azapi_resource.watcher.output.identity.principalId}
       Watcher name (use as the login name): ${azapi_resource.watcher.name}

    3. Start data collection:
         az rest --method post \
           --url "https://management.azure.com${azapi_resource.watcher.id}/start?api-version=2024-10-01-preview"

    4. Confirm data is landing, then add the ADX data source in Grafana:
         Cluster URL: ${azurerm_kusto_cluster.adx.uri}
         Auth:        Managed Identity   <-- NOT "Current User"

    5. Build alert rules, then set lock_down_public_access = true and re-apply.
  EOT
}
