locals {
  app_gateway_frontend_name = "appgw-private-frontend"
  app_gateway_backend_name  = "appgw-vmss-backend"
  app_gateway_port_name     = "https-443"
  app_gateway_settings_name = "backend-http-80"
  app_gateway_listener_name = "https-listener"
  sockperf_port_name        = "sockperf-tcp-12345"
  sockperf_backend_name     = "sockperf-tcp-backend"
  sockperf_listener_name    = "sockperf-tcp-listener"
  sockperf_probe_name       = "sockperf-tcp-probe"
}

resource "azurerm_resource_group" "provider" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "provider" {
  name                = "vnet-plsdc-provider"
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name
  address_space       = ["10.10.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "app_gateway" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.provider.name
  virtual_network_name = azurerm_virtual_network.provider.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_subnet" "pls" {
  name                                          = "snet-pls"
  resource_group_name                           = azurerm_resource_group.provider.name
  virtual_network_name                          = azurerm_virtual_network.provider.name
  address_prefixes                              = ["10.10.2.0/24"]
  private_link_service_network_policies_enabled = false
}

resource "azurerm_subnet" "backend" {
  name                 = "snet-backend"
  resource_group_name  = azurerm_resource_group.provider.name
  virtual_network_name = azurerm_virtual_network.provider.name
  address_prefixes     = ["10.10.3.0/24"]
}

resource "azurerm_public_ip" "egress" {
  name                = "pip-provider-nat"
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "egress" {
  name                    = "nat-provider-backend"
  location                = azurerm_resource_group.provider.location
  resource_group_name     = azurerm_resource_group.provider.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "egress" {
  nat_gateway_id       = azurerm_nat_gateway.egress.id
  public_ip_address_id = azurerm_public_ip.egress.id
}

resource "azurerm_subnet_nat_gateway_association" "backend" {
  subnet_id      = azurerm_subnet.backend.id
  nat_gateway_id = azurerm_nat_gateway.egress.id
}

resource "azurerm_network_security_group" "backend" {
  name                = "nsg-provider-backend"
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name

  security_rule {
    name                       = "AllowAppGatewayHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "10.10.1.0/24"
    destination_address_prefix = "10.10.3.0/24"
  }

  security_rule {
    name                       = "AllowAppGatewaySockPerf"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "12345"
    source_address_prefix      = "10.10.1.0/24"
    destination_address_prefix = "10.10.3.0/24"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "backend" {
  subnet_id                 = azurerm_subnet.backend.id
  network_security_group_id = azurerm_network_security_group.backend.id
}

resource "azurerm_application_gateway" "provider" {
  name                = "agw-plsdc-provider"
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name
  zones               = ["1", "2"]

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  autoscale_configuration {
    min_capacity = 2
    max_capacity = 4
  }

  gateway_ip_configuration {
    name      = "appgw-ip-configuration"
    subnet_id = azurerm_subnet.app_gateway.id
  }

  frontend_ip_configuration {
    name                          = local.app_gateway_frontend_name
    subnet_id                     = azurerm_subnet.app_gateway.id
    private_ip_address            = "10.10.1.10"
    private_ip_address_allocation = "Static"
  }

  frontend_port {
    name = local.app_gateway_port_name
    port = 443
  }

  frontend_port {
    name = local.sockperf_port_name
    port = 12345
  }

  ssl_certificate {
    name     = "app-tls"
    data     = var.tls_certificate_pfx_base64
    password = var.tls_certificate_password
  }

  backend_address_pool {
    name = local.app_gateway_backend_name
  }

  backend_http_settings {
    name                  = local.app_gateway_settings_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  probe {
    name                = local.sockperf_probe_name
    protocol            = "Tcp"
    port                = 12345
    interval            = 5
    timeout             = 5
    unhealthy_threshold = 2
  }

  backend {
    name               = local.sockperf_backend_name
    port               = 12345
    protocol           = "Tcp"
    probe_name         = local.sockperf_probe_name
    timeout_in_seconds = 120
  }

  http_listener {
    name                           = local.app_gateway_listener_name
    frontend_ip_configuration_name = local.app_gateway_frontend_name
    frontend_port_name             = local.app_gateway_port_name
    protocol                       = "Https"
    ssl_certificate_name           = "app-tls"
  }

  listener {
    name                           = local.sockperf_listener_name
    frontend_ip_configuration_name = local.app_gateway_frontend_name
    frontend_port_name             = local.sockperf_port_name
    protocol                       = "Tcp"
  }

  request_routing_rule {
    name                       = "route-to-provider-vmss"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = local.app_gateway_listener_name
    backend_address_pool_name  = local.app_gateway_backend_name
    backend_http_settings_name = local.app_gateway_settings_name
  }

  routing_rule {
    name                      = "route-sockperf-to-provider-vmss"
    priority                  = 110
    listener_name             = local.sockperf_listener_name
    backend_address_pool_name = local.app_gateway_backend_name
    backend_name              = local.sockperf_backend_name
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine_scale_set" "backend" {
  name                = "vmss-provider-app"
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name
  sku                 = var.vmss_sku
  instances           = 2
  admin_username      = var.admin_username
  upgrade_mode        = "Manual"
  zones               = ["1", "2"]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  network_interface {
    name                          = "nic-provider-app"
    primary                       = true
    enable_accelerated_networking = true

    ip_configuration {
      name      = "ipconfig"
      primary   = true
      subnet_id = azurerm_subnet.backend.id
      application_gateway_backend_address_pool_ids = [
        one([
          for pool in azurerm_application_gateway.provider.backend_address_pool : pool.id
          if pool.name == local.app_gateway_backend_name
        ])
      ]
    }
  }

  custom_data = base64encode(file("${path.module}/cloud-init.yaml"))
  tags        = var.tags

  depends_on = [
    azurerm_subnet_nat_gateway_association.backend,
    azurerm_subnet_network_security_group_association.backend,
  ]
}

resource "azurerm_private_link_service" "direct_connect" {
  name                = "pls-appgw-direct-connect"
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name

  destination_ip_address      = "10.10.1.10"
  visibility_subscription_ids = [var.consumer_subscription_id]

  nat_ip_configuration {
    name                       = "nat-primary"
    primary                    = true
    subnet_id                  = azurerm_subnet.pls.id
    private_ip_address         = "10.10.2.10"
    private_ip_address_version = "IPv4"
  }

  nat_ip_configuration {
    name                       = "nat-secondary"
    primary                    = false
    subnet_id                  = azurerm_subnet.pls.id
    private_ip_address         = "10.10.2.11"
    private_ip_address_version = "IPv4"
  }

  tags = var.tags

  depends_on = [azurerm_application_gateway.provider]
}
