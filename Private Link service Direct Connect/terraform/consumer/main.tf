resource "azurerm_resource_group" "consumer" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "workload" {
  name                = "vnet-consumer-workload"
  location            = azurerm_resource_group.consumer.location
  resource_group_name = azurerm_resource_group.consumer.name
  address_space       = ["10.20.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "workload" {
  name                 = "snet-consumer-vmss"
  resource_group_name  = azurerm_resource_group.consumer.name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_public_ip" "egress" {
  name                = "pip-consumer-nat"
  location            = azurerm_resource_group.consumer.location
  resource_group_name = azurerm_resource_group.consumer.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "egress" {
  name                    = "nat-consumer-workload"
  location                = azurerm_resource_group.consumer.location
  resource_group_name     = azurerm_resource_group.consumer.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "egress" {
  nat_gateway_id       = azurerm_nat_gateway.egress.id
  public_ip_address_id = azurerm_public_ip.egress.id
}

resource "azurerm_subnet_nat_gateway_association" "workload" {
  subnet_id      = azurerm_subnet.workload.id
  nat_gateway_id = azurerm_nat_gateway.egress.id
}

resource "azurerm_virtual_network" "endpoint" {
  name                = "vnet-consumer-endpoint"
  location            = azurerm_resource_group.consumer.location
  resource_group_name = azurerm_resource_group.consumer.name
  address_space       = ["10.21.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "endpoint" {
  name                              = "snet-private-endpoint"
  resource_group_name               = azurerm_resource_group.consumer.name
  virtual_network_name              = azurerm_virtual_network.endpoint.name
  address_prefixes                  = ["10.21.1.0/24"]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_virtual_network_peering" "workload_to_endpoint" {
  name                      = "peer-workload-to-endpoint"
  resource_group_name       = azurerm_resource_group.consumer.name
  virtual_network_name      = azurerm_virtual_network.workload.name
  remote_virtual_network_id = azurerm_virtual_network.endpoint.id
}

resource "azurerm_virtual_network_peering" "endpoint_to_workload" {
  name                      = "peer-endpoint-to-workload"
  resource_group_name       = azurerm_resource_group.consumer.name
  virtual_network_name      = azurerm_virtual_network.endpoint.name
  remote_virtual_network_id = azurerm_virtual_network.workload.id
}

resource "azurerm_network_security_group" "workload" {
  name                = "nsg-consumer-workload"
  location            = azurerm_resource_group.consumer.location
  resource_group_name = azurerm_resource_group.consumer.name

  security_rule {
    name                       = "AllowLoadBalancerProbe"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVnetHTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowPrivateLinkSockPerf"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "12345"
    source_address_prefix      = "10.20.1.0/24"
    destination_address_prefix = "10.21.1.10"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

resource "azurerm_lb" "consumer" {
  name                = "ilb-consumer-vmss"
  location            = azurerm_resource_group.consumer.location
  resource_group_name = azurerm_resource_group.consumer.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "consumer-private-frontend"
    subnet_id                     = azurerm_subnet.workload.id
    private_ip_address            = "10.20.1.10"
    private_ip_address_allocation = "Static"
  }

  tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "consumer" {
  name            = "consumer-vmss-backend"
  loadbalancer_id = azurerm_lb.consumer.id
}

resource "azurerm_lb_probe" "http" {
  name                = "http-80"
  loadbalancer_id     = azurerm_lb.consumer.id
  protocol            = "Tcp"
  port                = 80
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "http" {
  name                           = "http-80"
  loadbalancer_id                = azurerm_lb.consumer.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "consumer-private-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.consumer.id]
  probe_id                       = azurerm_lb_probe.http.id
}

resource "azurerm_linux_virtual_machine_scale_set" "consumer" {
  name                = "vmss-consumer-client"
  location            = azurerm_resource_group.consumer.location
  resource_group_name = azurerm_resource_group.consumer.name
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
    name                          = "nic-consumer-client"
    primary                       = true
    enable_accelerated_networking = true

    ip_configuration {
      name                                   = "ipconfig"
      primary                                = true
      subnet_id                              = azurerm_subnet.workload.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.consumer.id]
    }
  }

  custom_data = base64encode(file("${path.module}/cloud-init.yaml"))
  tags        = var.tags

  depends_on = [
    azurerm_subnet_nat_gateway_association.workload,
    azurerm_subnet_network_security_group_association.workload,
  ]
}

resource "azurerm_private_endpoint" "provider" {
  name                          = "pe-provider-plsdc"
  location                      = azurerm_resource_group.consumer.location
  resource_group_name           = azurerm_resource_group.consumer.name
  subnet_id                     = azurerm_subnet.endpoint.id
  custom_network_interface_name = "nic-pe-provider-plsdc"

  ip_configuration {
    name               = "plsdc"
    private_ip_address = "10.21.1.10"
  }

  private_service_connection {
    name                           = "connection-to-provider-plsdc"
    private_connection_resource_id = var.private_link_service_id
    is_manual_connection           = true
    request_message                = "Cross-tenant PLS Direct Connect request"
  }

  tags = var.tags
}

resource "azurerm_private_dns_zone" "application" {
  name                = "plsdc.internal"
  resource_group_name = azurerm_resource_group.consumer.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "workload" {
  name                  = "link-consumer-workload"
  resource_group_name   = azurerm_resource_group.consumer.name
  private_dns_zone_name = azurerm_private_dns_zone.application.name
  virtual_network_id    = azurerm_virtual_network.workload.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "endpoint" {
  name                  = "link-consumer-endpoint"
  resource_group_name   = azurerm_resource_group.consumer.name
  private_dns_zone_name = azurerm_private_dns_zone.application.name
  virtual_network_id    = azurerm_virtual_network.endpoint.id
}

resource "azurerm_private_dns_a_record" "application" {
  name                = "app"
  zone_name           = azurerm_private_dns_zone.application.name
  resource_group_name = azurerm_resource_group.consumer.name
  ttl                 = 300
  records             = ["10.21.1.10"]
  tags                = var.tags
}
