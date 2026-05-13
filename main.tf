variable "prefix" {
  default = "sonar"
}

resource "azurerm_resource_group" "rg" {
  name     = "sonar-rg"
  location = "westus2"
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                         = "myaks"
  location                     = "eastasia"
  resource_group_name          = azurerm_resource_group.rg.name
  dns_prefix                   = "myaks-dns"
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 168
  workload_identity_enabled    = true
  oidc_issuer_enabled          = true

  default_node_pool {
    name                 = "agentpool"
    node_count           = 1
    vm_size              = "Standard_DS2_v2"
    auto_scaling_enabled = true
    max_count            = 2
    min_count            = 1
    zones                = ["1", ]

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0

    }
  }

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = all
  }
}

resource "azurerm_container_registry" "acr" {
  name                = "myacr198"
  resource_group_name = azurerm_resource_group.rg.name
  location            = "centralindia"
  sku                 = "Basic"

}

resource "azurerm_virtual_network" "vnet" {
  name                = "sonar-server-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]

}

resource "azurerm_subnet" "sub1" {
  name                            = "subnet1"
  resource_group_name             = azurerm_resource_group.rg.name
  virtual_network_name            = azurerm_virtual_network.vnet.name
  address_prefixes                = ["10.0.1.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "sub2" {
  name                            = "subnet2"
  resource_group_name             = azurerm_resource_group.rg.name
  virtual_network_name            = azurerm_virtual_network.vnet.name
  address_prefixes                = ["10.0.2.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "default" {
  name                            = "default"
  resource_group_name             = azurerm_resource_group.rg.name
  virtual_network_name            = azurerm_virtual_network.vnet.name
  address_prefixes                = ["10.0.0.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_network_security_group" "nsg" {
  location            = azurerm_resource_group.rg.location
  name                = "sonar-server-nsg"
  resource_group_name = azurerm_resource_group.rg.name
  security_rule = [
    {
      access                                     = "Allow"
      description                                = null
      destination_address_prefix                 = "*"
      destination_address_prefixes               = []
      destination_application_security_group_ids = []
      destination_port_range                     = "22"
      destination_port_ranges                    = []
      direction                                  = "Inbound"
      name                                       = "SSH"
      priority                                   = 300
      protocol                                   = "Tcp"
      source_address_prefix                      = "*"
      source_address_prefixes                    = []
      source_application_security_group_ids      = []
      source_port_range                          = "*"
      source_port_ranges                         = []
    },
    {
      access                                     = "Allow"
      description                                = null
      destination_address_prefix                 = "*"
      destination_address_prefixes               = []
      destination_application_security_group_ids = []
      destination_port_range                     = "9000"
      destination_port_ranges                    = []
      direction                                  = "Inbound"
      name                                       = "allow9000"
      priority                                   = 310
      protocol                                   = "*"
      source_address_prefix                      = "*"
      source_address_prefixes                    = []
      source_application_security_group_ids      = []
      source_port_range                          = "*"
      source_port_ranges                         = []
    },
  ]
  tags = {}
}

resource "azurerm_public_ip" "pub_ip" {
  name                = "sonar-server-ip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Regional"
  tags                = {}
  zones = [
    "3",
  ]
}

resource "azurerm_network_interface" "nic" {
  name                = "sonar-server929_z3"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.default.id
    public_ip_address_id          = azurerm_public_ip.pub_ip.id
    private_ip_address_allocation = "Dynamic"
  }
}


resource "azurerm_virtual_machine" "vm" {
  name                  = "${var.prefix}-vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size               = "Standard_B2als_v2"

  storage_image_reference {
    offer     = "ubuntu-24_04-lts"
    publisher = "canonical"
    sku       = "server"
    version   = "latest"
  }

  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    disk_size_gb      = 30
    os_type           = "Linux"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${var.prefix}-vm"
    admin_username = "azureuser"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDPbQCQy4mRtitCx1tdgf/tK0oySZpwnOl+J3ZsvhH2cgMTOF+P7g0Mf9z2gRoRoraBNXTNKQg+BLuObDcD2Q7i3VhTQpYdEFY6vYKY1HxA21wNg9/b7qwZlWz0jxMxDXKsScSrW9nOb0yKFS/ykSkyR2YrR27pM9UxyF0UWy3qKCiFyHg1yHEIVwfTXakpLCjG4o/CHgP9MUzyvbYUcuz2FAzMQkL+4Bt+XIAdwdYkycZi/geYu9pUNS7U6MbxufKZCa9oVry9mDpr5RuayZu0/Rgj+umbibWJxRxX19TNIUcjYNdh4/RgG9UZhOMP7jrCIlDluXelyQsXy6z9kNEY46I0w4BbBpdAK5JGa/4sX+QSvH6jJrCOnwtlCLDChuaVKD2sOXhIXsBJN5k+9lKjAO5RZUc9yPPp7NOTk3LjXPVQPKGhc82Kh30TGhh0UGhz8tI8xrTiRdkU4yNny+R5OGMajVMR2n5Nd5rbhOG8C1X47xgAcXZdsfYVcAT2OU= generated-by-azure"
      path     = "/home/azureuser/.ssh/authorized_keys"
    }
  }

}
