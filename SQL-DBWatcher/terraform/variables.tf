#############################################
# Existing resources you must supply
#############################################

variable "sqlmi_name" {
  type        = string
  description = "Name of the EXISTING Azure SQL Managed Instance to monitor."
}

variable "sqlmi_resource_group_name" {
  type        = string
  description = "Resource group of the existing SQL Managed Instance."
}

variable "vnet_name" {
  type        = string
  description = "Name of the existing virtual network that will host the inbound private endpoint for Grafana."
}

variable "vnet_resource_group_name" {
  type        = string
  description = "Resource group of the existing virtual network."
}

variable "private_endpoint_subnet_name" {
  type        = string
  description = "Subnet for the inbound Grafana private endpoint. Must NOT be the SQL MI delegated subnet, and must have private endpoint network policies compatible with private endpoints."
}

#############################################
# PoC resources this module creates
#############################################

variable "resource_group_name" {
  type        = string
  description = "Resource group to create for the PoC."
  default     = "rg-dbwatcher-grafana-poc"
}

variable "location" {
  type        = string
  description = "Azure region. Should match the SQL MI region where possible to avoid bandwidth cost. Database Watcher is only available in a subset of regions - check the docs before changing."
  default     = "East US"
}

variable "name_prefix" {
  type        = string
  description = "Short prefix used in generated resource names. Lowercase alphanumeric."
  default     = "dbw"

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.name_prefix))
    error_message = "name_prefix must be 2-10 lowercase alphanumeric characters."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all created resources."
  default = {
    workload = "dbwatcher-private-alerting-poc"
    owner    = "platform-data"
  }
}

#############################################
# Azure Data Explorer
#############################################

variable "adx_sku_name" {
  type        = string
  description = "ADX cluster SKU. Both SKU availability and live capacity are region specific - verify with: az rest --method get --url \"https://management.azure.com/subscriptions/<sub>/providers/Microsoft.Kusto/locations/<region>/skus?api-version=2024-04-13\""
  default     = "Dev(No SLA)_Standard_D11_v2"
}

variable "adx_location" {
  type        = string
  description = "Region for the ADX cluster and database. Defaults to var.location; override only when the primary region has no Kusto capacity (InsufficientResourcesForSubscription)."
  default     = null
}

variable "adx_sku_capacity" {
  type        = number
  description = "ADX cluster instance count. Dev SKUs support only 1; Standard tier requires at least 2."
  default     = 1
}

variable "adx_database_name" {
  type        = string
  description = "Name of the ADX database used as the Database Watcher data store."
  default     = "sqlwatcher"
}

variable "adx_hot_cache_period" {
  type        = string
  description = "ISO8601 hot cache period."
  default     = "P7D"
}

variable "adx_retention_period" {
  type        = string
  description = "ISO8601 soft delete / retention period."
  default     = "P35D"
}

#############################################
# Azure Managed Grafana
#############################################

variable "grafana_major_version" {
  type        = number
  description = "Grafana major version. Allowed values are 12 and 13."
  default     = 13

  validation {
    condition     = contains([12, 13], var.grafana_major_version)
    error_message = "grafana_major_version must be 12 or 13."
  }
}

variable "grafana_sku_size" {
  type        = string
  description = "X1 supports 500 alert rules per org, X2 supports 1000. X1 is ample for the ~19 Database Watcher rules. NOTE: you cannot downgrade from X2 back to X1."
  default     = "X1"

  validation {
    condition     = contains(["X1", "X2"], var.grafana_sku_size)
    error_message = "grafana_sku_size must be X1 or X2."
  }
}

variable "grafana_zone_redundant" {
  type        = bool
  description = "Enable zone redundancy for the Grafana workspace."
  default     = false
}

variable "assign_grafana_admin_to_caller" {
  type        = bool
  description = "Assign the Grafana Admin role so you can sign in and build alert rules. Requires permission to create role assignments."
  default     = true
}

variable "grafana_admin_principal_id" {
  type        = string
  description = "Object ID to grant Grafana Admin. Defaults to the identity running Terraform."
  default     = null
}

variable "grafana_admin_extra_principal_ids" {
  type        = list(string)
  description = "Additional object IDs to grant Grafana Admin, for example a break-glass tenant admin used from the jumpbox. Role propagation can take up to an hour."
  default     = []
}

variable "create_alert_rule_identity" {
  type        = bool
  description = "Create a user-assigned identity for Azure Monitor alert rules and set it as the watcher default. Required before the Alert templates blade will create any rule. Must be separate from the watcher identity."
  default     = true
}

#############################################
# Network posture
#############################################

variable "lock_down_public_access" {
  type        = bool
  description = <<-EOT
    PHASE SWITCH for the PoC.

    false (phase 1) - ADX and Grafana keep public network access enabled so you can
                      build and prove the pipeline end to end without fighting DNS.

    true  (phase 2) - ADX and Grafana public network access are DISABLED. This is the
                      go/no-go gate: everything must still work over Private Link only.
                      Do not flip this until the shared private link connections and the
                      Grafana managed private endpoint have all been APPROVED.
  EOT
  default     = false
}

variable "create_grafana_private_dns_zone" {
  type        = bool
  description = "Create and link privatelink.grafana.azure.com. Set to false if you manage private DNS centrally (common in hub-and-spoke)."
  default     = true
}

#############################################
# Phase 2 verification path
#
# Lock-down removes public access to ADX and Grafana, including from the machine
# running Terraform. These give you a route in so the gate can actually be tested.
#############################################

variable "create_admin_peering" {
  type        = bool
  description = "Peer an existing admin/jumpbox VNet into the workload VNet and link the Grafana private DNS zone to it."
  default     = false
}

variable "admin_vnet_name" {
  type        = string
  description = "Name of the existing admin/jumpbox VNet to peer. Required when create_admin_peering is true."
  default     = null
}

variable "admin_vnet_resource_group_name" {
  type        = string
  description = "Resource group of the admin/jumpbox VNet."
  default     = null
}

variable "create_adx_private_endpoint" {
  type        = bool
  description = "Create a private endpoint and DNS zone for ADX so humans can run KQL after lock-down. The watcher and Grafana have their own service-to-service paths; neither helps you query the cluster."
  default     = false
}

variable "create_jumpbox" {
  type        = bool
  description = "Create a Windows jumpbox inside the workload VNet. Without one the Phase 2 gate cannot be verified, because Grafana and ADX are only reachable from inside the VNet."
  default     = false
}

variable "jumpbox_vm_size" {
  type        = string
  description = "Jumpbox VM size. B-series is enough for a browser and a shell."
  default     = "Standard_B2ms"
}

variable "jumpbox_admin_username" {
  type        = string
  description = "Local administrator name on the jumpbox. Cannot be 'admin' or 'administrator'."
  default     = "azureadmin"
}

variable "jumpbox_allowed_source_ip" {
  type        = string
  description = "Single public IP allowed to RDP to the jumpbox, without a mask. Only used when jumpbox_public_ip is true."
  default     = null
}

variable "jumpbox_public_ip" {
  type        = bool
  description = "Give the jumpbox a public IP for RDP. Many subscriptions block public IP creation entirely; when they do, leave this false and drive the VM with 'az vm run-command invoke'."
  default     = false
}

variable "register_resource_providers" {
  type        = bool
  description = <<-EOT
    Register the resource providers this module needs (Microsoft.DatabaseWatcher,
    Microsoft.Dashboard, Microsoft.Kusto, Microsoft.Network).

    Requires subscription-level permission to register providers. Set to false if
    your deploying identity is scoped to a resource group - in that case have a
    subscription Owner run scripts/preflight.ps1 once beforehand.
  EOT
  default     = true
}
