terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}

  # azurerm only auto-registers a fixed set of resource providers, and neither
  # Microsoft.DatabaseWatcher nor Microsoft.Dashboard is in it. Without this you
  # get a confusing mid-apply failure such as:
  #   "API version '2024-10-01-preview' was not found for 'Microsoft.DatabaseWatcher'"
  # Registering here is idempotent - already-registered providers are a no-op.
  #
  # If the identity running Terraform lacks subscription-level permission to
  # register providers, set this to [] and have a subscription Owner run
  # scripts/preflight.ps1 once instead.
  resource_providers_to_register = var.register_resource_providers ? [
    "Microsoft.DatabaseWatcher",
    "Microsoft.Dashboard",
    "Microsoft.Kusto",
    "Microsoft.Network",
  ] : []
}

provider "azapi" {}

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  suffix = random_string.suffix.result

  adx_location = coalesce(var.adx_location, var.location)

  # Private DNS zone names use the compact region form: "Canada East" -> "canadaeast".
  adx_region_slug = replace(lower(local.adx_location), " ", "")

  # SQL MI FQDN looks like: <name>.<dns-zone-partition>.database.windows.net
  # The shared private link dnsZone value is the SECOND segment of that FQDN.
  sqlmi_dns_zone = split(".", data.azurerm_mssql_managed_instance.target.fqdn)[1]

  # ADX cluster URI looks like: https://<name>.<region>.kusto.windows.net
  # The shared private link dnsZone value is the SECOND segment of that host name.
  adx_host     = replace(azurerm_kusto_cluster.adx.uri, "https://", "")
  adx_dns_zone = split(".", local.adx_host)[1]
}

#############################################
# Existing resources (already in the subscription)
#############################################

data "azurerm_mssql_managed_instance" "target" {
  name                = var.sqlmi_name
  resource_group_name = var.sqlmi_resource_group_name
}

data "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  resource_group_name = var.vnet_resource_group_name
}

# Subnet used for the inbound private endpoint to Azure Managed Grafana.
# Must NOT be the SQL MI delegated subnet.
data "azurerm_subnet" "private_endpoints" {
  name                 = var.private_endpoint_subnet_name
  virtual_network_name = data.azurerm_virtual_network.vnet.name
  resource_group_name  = var.vnet_resource_group_name
}

#############################################
# Resource group for the PoC
#############################################

resource "azurerm_resource_group" "poc" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

#############################################
# Azure Data Explorer - the monitoring data store
#############################################

resource "azurerm_kusto_cluster" "adx" {
  name                = "adx${var.name_prefix}${local.suffix}"
  location            = local.adx_location
  resource_group_name = azurerm_resource_group.poc.name

  sku {
    name     = var.adx_sku_name
    capacity = var.adx_sku_capacity
  }

  # Database Watcher ingests through the streaming path. Without this the watcher
  # creates its table schema but no rows ever land, with no ingestion failures logged.
  # Auto-enabled only for clusters the watcher creates itself, never for a BYO cluster.
  streaming_ingestion_enabled = true

  # Phase 1 of the PoC leaves this true so you can prove the pipeline end to end.
  # Phase 2 sets lock_down_public_access = true, which is the whole point of the design.
  public_network_access_enabled = !var.lock_down_public_access

  tags = var.tags
}

resource "azurerm_kusto_database" "watcher" {
  name                = var.adx_database_name
  resource_group_name = azurerm_resource_group.poc.name
  location            = local.adx_location
  cluster_name        = azurerm_kusto_cluster.adx.name

  hot_cache_period   = var.adx_hot_cache_period
  soft_delete_period = var.adx_retention_period
}

#############################################
# Alert rule identity
#
# Azure Monitor log search alert rules created from the watcher's built-in
# templates need their OWN identity to query the data store. Microsoft is explicit
# that this must not be the watcher identity - the watcher is an Admin on the
# database, and alert rules only need to read.
#
# Without this set, the Alert templates blade refuses to create any rule:
#   "An alert rule identity is required to create alert rules but hasn't been selected."
#############################################

resource "azurerm_user_assigned_identity" "alert_rules" {
  count               = var.create_alert_rule_identity ? 1 : 0
  name                = "id-${var.name_prefix}-alerts-${local.suffix}"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  tags                = var.tags
}

# Lets the alert rule identity enumerate the cluster.
resource "azurerm_role_assignment" "alert_rules_adx_reader" {
  count                = var.create_alert_rule_identity ? 1 : 0
  scope                = azurerm_kusto_cluster.adx.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.alert_rules[0].principal_id
}

# Read-only on the data itself. Viewer, never Admin.
resource "azurerm_kusto_database_principal_assignment" "alert_rules_viewer" {
  count               = var.create_alert_rule_identity ? 1 : 0
  name                = "alertrulesviewer"
  resource_group_name = azurerm_resource_group.poc.name
  cluster_name        = azurerm_kusto_cluster.adx.name
  database_name       = azurerm_kusto_database.watcher.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = azurerm_user_assigned_identity.alert_rules[0].principal_id
  principal_type = "App"
  role           = "Viewer"
}

#############################################
# Database Watcher
# No azurerm resource exists for Microsoft.DatabaseWatcher, so we use AzAPI.
#############################################

resource "azapi_resource" "watcher" {
  type      = "Microsoft.DatabaseWatcher/watchers@2024-10-01-preview"
  name      = "dbw-${var.name_prefix}-${local.suffix}"
  parent_id = azurerm_resource_group.poc.id
  location  = azurerm_resource_group.poc.location
  tags      = var.tags

  body = {
    properties = {
      defaultAlertRuleIdentityResourceId = var.create_alert_rule_identity ? azurerm_user_assigned_identity.alert_rules[0].id : null

      datastore = {
        adxClusterResourceId = azurerm_kusto_cluster.adx.id
        # Required for the "adx" and "free" offerings, even though it is only a label.
        kustoClusterDisplayName = azurerm_kusto_cluster.adx.name
        kustoClusterUri         = azurerm_kusto_cluster.adx.uri
        kustoDataIngestionUri   = azurerm_kusto_cluster.adx.data_ingestion_uri
        kustoDatabaseName       = azurerm_kusto_database.watcher.name
        kustoManagementUrl      = "https://portal.azure.com/"
        kustoOfferingType       = "adx"
      }
    }
  }

  identity {
    type = "SystemAssigned"
  }

  response_export_values = ["identity.principalId"]

  schema_validation_enabled = true
}

# The watcher creates and writes tables in the ADX database, so it needs Admin
# on the database (not just Ingestor).
resource "azurerm_kusto_database_principal_assignment" "watcher_admin" {
  name                = "watcheradmin"
  resource_group_name = azurerm_resource_group.poc.name
  cluster_name        = azurerm_kusto_cluster.adx.name
  database_name       = azurerm_kusto_database.watcher.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = azapi_resource.watcher.output.identity.principalId
  principal_type = "App"
  role           = "Admin"

  # principalId is unknown at plan time, so any watcher change replaces this
  # assignment and ingestion stops until it is recreated - with status still "Running".
  lifecycle {
    ignore_changes = [principal_id]
  }
}

# The SQL MI to monitor.
resource "azapi_resource" "watcher_target_sqlmi" {
  type      = "Microsoft.DatabaseWatcher/watchers/targets@2024-10-01-preview"
  name      = "target-${var.sqlmi_name}"
  parent_id = azapi_resource.watcher.id

  body = {
    properties = {
      targetType               = "SqlMi"
      targetAuthenticationType = "Aad"
      connectionServerName     = data.azurerm_mssql_managed_instance.target.fqdn
      sqlMiResourceId          = data.azurerm_mssql_managed_instance.target.id
      connectionTcpPort        = 1433
      readIntent               = false
    }
  }

  schema_validation_enabled = true
}

#############################################
# Watcher -> private connectivity
# These create PENDING private endpoint connections on the SQL MI and the ADX
# cluster. They must be APPROVED before traffic flows. See scripts/approve-private-endpoints.ps1
#############################################

resource "azapi_resource" "watcher_splr_sqlmi" {
  type      = "Microsoft.DatabaseWatcher/watchers/sharedPrivateLinkResources@2024-10-01-preview"
  name      = "splr-sqlmi"
  parent_id = azapi_resource.watcher.id

  body = {
    properties = {
      privateLinkResourceId = data.azurerm_mssql_managed_instance.target.id
      groupId               = "managedInstance"
      dnsZone               = local.sqlmi_dns_zone
      requestMessage        = "Database Watcher private connectivity to SQL MI"
    }
  }

  schema_validation_enabled = true
}

resource "azapi_resource" "watcher_splr_adx" {
  type      = "Microsoft.DatabaseWatcher/watchers/sharedPrivateLinkResources@2024-10-01-preview"
  name      = "splr-adx"
  parent_id = azapi_resource.watcher.id

  body = {
    properties = {
      privateLinkResourceId = azurerm_kusto_cluster.adx.id
      groupId               = "cluster"
      dnsZone               = local.adx_dns_zone
      requestMessage        = "Database Watcher private connectivity to ADX"
    }
  }

  depends_on = [azurerm_kusto_database.watcher]

  schema_validation_enabled = true
}

#############################################
# Azure Managed Grafana - the alert evaluation engine
#############################################

resource "azurerm_dashboard_grafana" "amg" {
  name                = "amg-${var.name_prefix}-${local.suffix}"
  resource_group_name = azurerm_resource_group.poc.name
  location            = azurerm_resource_group.poc.location

  # Standard is required: Essential has no alerting and no private endpoints.
  sku                   = "Standard"
  sku_size              = var.grafana_sku_size
  grafana_major_version = var.grafana_major_version

  # Required for service account tokens, which is how alert rules get provisioned
  # through the Grafana API instead of being hand-built in the UI.
  api_key_enabled = true

  # Useful when your SMTP relay or ITSM endpoint needs an allow-list.
  deterministic_outbound_ip_enabled = true

  # Phase 2 disables this and forces access through the private endpoint.
  public_network_access_enabled = !var.lock_down_public_access

  zone_redundancy_enabled = var.grafana_zone_redundant

  # AMG supports exactly ONE managed identity: system OR user-assigned.
  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Grafana reads the monitoring data. Viewer on the database is all it needs.
resource "azurerm_kusto_database_principal_assignment" "grafana_viewer" {
  name                = "grafanaviewer"
  resource_group_name = azurerm_resource_group.poc.name
  cluster_name        = azurerm_kusto_cluster.adx.name
  database_name       = azurerm_kusto_database.watcher.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = azurerm_dashboard_grafana.amg.identity[0].principal_id
  principal_type = "App"
  role           = "Viewer"
}

# Reader on the cluster lets the Grafana data source enumerate databases.
resource "azurerm_role_assignment" "grafana_adx_reader" {
  scope                = azurerm_kusto_cluster.adx.id
  role_definition_name = "Reader"
  principal_id         = azurerm_dashboard_grafana.amg.identity[0].principal_id
}

# Let the operator running Terraform administer the Grafana workspace.
resource "azurerm_role_assignment" "grafana_admin" {
  count                = var.assign_grafana_admin_to_caller ? 1 : 0
  scope                = azurerm_dashboard_grafana.amg.id
  role_definition_name = "Grafana Admin"
  principal_id         = coalesce(var.grafana_admin_principal_id, data.azurerm_client_config.current.object_id)
}

# Anyone else who needs the UI. Grafana RBAC is separate from Azure RBAC, so being
# Owner on the subscription grants no access to the workspace itself.
resource "azurerm_role_assignment" "grafana_admin_extra" {
  for_each             = toset(var.grafana_admin_extra_principal_ids)
  scope                = azurerm_dashboard_grafana.amg.id
  role_definition_name = "Grafana Admin"
  principal_id         = each.value
}

#############################################
# Grafana -> ADX over a managed private endpoint
#
# NOTE: this resource does NOT approve the connection on the ADX side.
# Approve it with scripts/approve-private-endpoints.ps1 (or the portal).
#############################################

resource "azurerm_dashboard_grafana_managed_private_endpoint" "adx" {
  grafana_id                   = azurerm_dashboard_grafana.amg.id
  name                         = "mpe-adx"
  location                     = azurerm_dashboard_grafana.amg.location
  private_link_resource_id     = azurerm_kusto_cluster.adx.id
  group_ids                    = ["cluster"]
  private_link_resource_region = azurerm_kusto_cluster.adx.location
}

#############################################
# Users -> Grafana over an inbound private endpoint
#############################################

resource "azurerm_private_dns_zone" "grafana" {
  count               = var.create_grafana_private_dns_zone ? 1 : 0
  name                = "privatelink.grafana.azure.com"
  resource_group_name = azurerm_resource_group.poc.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "grafana" {
  count                 = var.create_grafana_private_dns_zone ? 1 : 0
  name                  = "link-${var.vnet_name}"
  resource_group_name   = azurerm_resource_group.poc.name
  private_dns_zone_name = azurerm_private_dns_zone.grafana[0].name
  virtual_network_id    = data.azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "grafana" {
  name                = "pe-grafana-${local.suffix}"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  subnet_id           = data.azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-grafana"
    private_connection_resource_id = azurerm_dashboard_grafana.amg.id
    subresource_names              = ["grafana"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.create_grafana_private_dns_zone ? [1] : []
    content {
      name                 = "grafana-dns"
      private_dns_zone_ids = [azurerm_private_dns_zone.grafana[0].id]
    }
  }
}

#############################################
# Phase 2 verification path
#
# Once lock_down_public_access = true, ADX and Grafana are unreachable from the
# public internet - including from the workstation running Terraform. Without a
# route into the VNet you cannot answer the only question the gate exists to ask:
# does this still work over Private Link alone?
#
# This peers an existing admin/jumpbox VNet into the SQL MI VNet and gives ADX a
# private endpoint of its own. The Grafana managed private endpoint is a data-plane
# path for Grafana only - nothing else can query the cluster once it is locked down.
#############################################

data "azurerm_virtual_network" "admin" {
  count               = var.create_admin_peering ? 1 : 0
  name                = var.admin_vnet_name
  resource_group_name = var.admin_vnet_resource_group_name
}

resource "azurerm_virtual_network_peering" "admin_to_workload" {
  count                        = var.create_admin_peering ? 1 : 0
  name                         = "peer-to-${var.vnet_name}"
  resource_group_name          = var.admin_vnet_resource_group_name
  virtual_network_name         = var.admin_vnet_name
  remote_virtual_network_id    = data.azurerm_virtual_network.vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
}

resource "azurerm_virtual_network_peering" "workload_to_admin" {
  count                        = var.create_admin_peering ? 1 : 0
  name                         = "peer-to-${var.admin_vnet_name}"
  resource_group_name          = var.vnet_resource_group_name
  virtual_network_name         = var.vnet_name
  remote_virtual_network_id    = data.azurerm_virtual_network.admin[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
}

# Peering gives IP reachability; the admin VNet still needs the private DNS zone
# or the Grafana FQDN keeps resolving to its public address.
resource "azurerm_private_dns_zone_virtual_network_link" "grafana_admin" {
  count                 = var.create_admin_peering && var.create_grafana_private_dns_zone ? 1 : 0
  name                  = "link-${var.admin_vnet_name}"
  resource_group_name   = azurerm_resource_group.poc.name
  private_dns_zone_name = azurerm_private_dns_zone.grafana[0].name
  virtual_network_id    = data.azurerm_virtual_network.admin[0].id
  registration_enabled  = false
  tags                  = var.tags
}

#############################################
# ADX private endpoint for humans
#
# Separate from the watcher's shared private link and Grafana's managed private
# endpoint. Both of those are service-to-service. This is the one that lets you
# run KQL after lock-down.
#############################################

resource "azurerm_private_dns_zone" "adx" {
  count               = var.create_adx_private_endpoint ? 1 : 0
  name                = "privatelink.${local.adx_region_slug}.kusto.windows.net"
  resource_group_name = azurerm_resource_group.poc.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "adx_workload" {
  count                 = var.create_adx_private_endpoint ? 1 : 0
  name                  = "link-${var.vnet_name}"
  resource_group_name   = azurerm_resource_group.poc.name
  private_dns_zone_name = azurerm_private_dns_zone.adx[0].name
  virtual_network_id    = data.azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "adx_admin" {
  count                 = var.create_adx_private_endpoint && var.create_admin_peering ? 1 : 0
  name                  = "link-${var.admin_vnet_name}"
  resource_group_name   = azurerm_resource_group.poc.name
  private_dns_zone_name = azurerm_private_dns_zone.adx[0].name
  virtual_network_id    = data.azurerm_virtual_network.admin[0].id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "adx" {
  count               = var.create_adx_private_endpoint ? 1 : 0
  name                = "pe-adx-${local.suffix}"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  subnet_id           = data.azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-adx"
    private_connection_resource_id = azurerm_kusto_cluster.adx.id
    subresource_names              = ["cluster"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "adx-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.adx[0].id]
  }
}

#############################################
# Jumpbox
#
# The only way to prove the Phase 2 gate. From inside the VNet the private DNS
# zones resolve, so the Grafana UI and ADX both work while public access is off.
# From anywhere else they do not, which is the point.
#
# Deallocate it when you are not testing - it bills per hour and carries a
# Windows licence charge.
#############################################

resource "random_password" "jumpbox" {
  count            = var.create_jumpbox ? 1 : 0
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Some subscriptions block public IP creation outright, and this one does. When that
# is the case, reach the VM with 'az vm run-command invoke', which uses the guest
# agent's outbound channel instead of any inbound path.
resource "azurerm_public_ip" "jumpbox" {
  count               = var.create_jumpbox && var.jumpbox_public_ip ? 1 : 0
  name                = "pip-jump-${local.suffix}"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  # Subscriptions gated on the public IP feature get an ip_tag stamped on by Azure.
  # Reverting it forces replacement, which changes the address you RDP to.
  lifecycle {
    ignore_changes = [ip_tags, zones]
  }
}

resource "azurerm_network_interface" "jumpbox" {
  count               = var.create_jumpbox ? 1 : 0
  name                = "nic-jump-${local.suffix}"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.private_endpoints.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.jumpbox_public_ip ? azurerm_public_ip.jumpbox[0].id : null
  }
}

# The subnet NSG already denies inbound from the internet. Both the subnet and NIC
# layers must allow the traffic, so the rule goes on the existing subnet NSG.
resource "azurerm_network_security_rule" "jumpbox_rdp" {
  count                       = var.create_jumpbox && var.jumpbox_public_ip ? 1 : 0
  name                        = "allow_jumpbox_rdp"
  resource_group_name         = element(split("/", data.azurerm_subnet.private_endpoints.network_security_group_id), 4)
  network_security_group_name = element(split("/", data.azurerm_subnet.private_endpoints.network_security_group_id), 8)
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = var.jumpbox_allowed_source_ip
  destination_address_prefix  = "*"
}

resource "azurerm_windows_virtual_machine" "jumpbox" {
  count                 = var.create_jumpbox ? 1 : 0
  name                  = "vm-jump-${local.suffix}"
  location              = azurerm_resource_group.poc.location
  resource_group_name   = azurerm_resource_group.poc.name
  size                  = var.jumpbox_vm_size
  admin_username        = var.jumpbox_admin_username
  admin_password        = random_password.jumpbox[0].result
  network_interface_ids = [azurerm_network_interface.jumpbox[0].id]
  tags                  = var.tags

  secure_boot_enabled = true
  vtpm_enabled        = true

  # The Azure Edition image is hotpatch enabled and rejects any other patch mode.
  patch_mode = "AutomaticByPlatform"

  # Lets the jumpbox query ADX with an IMDS token, so the gate can be verified
  # without copying credentials onto the VM.
  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-azure-edition"
    version   = "latest"
  }
}

resource "azurerm_kusto_database_principal_assignment" "jumpbox_viewer" {
  count               = var.create_jumpbox ? 1 : 0
  name                = "jumpboxviewer"
  resource_group_name = azurerm_resource_group.poc.name
  cluster_name        = azurerm_kusto_cluster.adx.name
  database_name       = azurerm_kusto_database.watcher.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = azurerm_windows_virtual_machine.jumpbox[0].identity[0].principal_id
  principal_type = "App"
  role           = "Viewer"
}
