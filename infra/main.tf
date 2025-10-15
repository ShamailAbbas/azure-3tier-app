# ############################################################
# # Provider & Resource Group
# ############################################################
# terraform {
#   required_providers {
#     azurerm = {
#       source  = "hashicorp/azurerm"
#       version = "~> 3.0"
#     }
#   }
# }

# provider "azurerm" {
#   features {}
#   subscription_id = "fa244b65-8825-4e2c-a86b-21117f3998ba"
# }

# resource "azurerm_resource_group" "rg" {
#   name     = "my3tierapp-rg-multi-vm"
#   location = "UK South"
# }

# ############################################################
# # Networking (VNet + Subnets)
# ############################################################
# resource "azurerm_virtual_network" "vnet" {
#   name                = "my3tier-vnet"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   address_space       = ["10.0.0.0/16"]
# }

# resource "azurerm_subnet" "appgw" {
#   name                 = "appgw-subnet"
#   resource_group_name  = azurerm_resource_group.rg.name
#   virtual_network_name = azurerm_virtual_network.vnet.name
#   address_prefixes     = ["10.0.1.0/24"]
# }

# resource "azurerm_subnet" "backend" {
#   name                 = "backend-subnet"
#   resource_group_name  = azurerm_resource_group.rg.name
#   virtual_network_name = azurerm_virtual_network.vnet.name
#   address_prefixes     = ["10.0.2.0/24"]
# }

# resource "azurerm_subnet" "db" {
#   name                 = "db-subnet"
#   resource_group_name  = azurerm_resource_group.rg.name
#   virtual_network_name = azurerm_virtual_network.vnet.name
#   address_prefixes     = ["10.0.3.0/24"]

#   delegation {
#     name = "mysql-delegation"
#     service_delegation {
#       name = "Microsoft.DBforMySQL/flexibleServers"
#       actions = [
#         "Microsoft.Network/virtualNetworks/subnets/join/action",
#       ]
#     }
#   }
# }

# resource "azurerm_subnet" "bastion" {
#   name                 = "AzureBastionSubnet"
#   resource_group_name  = azurerm_resource_group.rg.name
#   virtual_network_name = azurerm_virtual_network.vnet.name
#   address_prefixes     = ["10.0.4.0/27"]
# }

# ############################################################
# # Private DNS Zone for MySQL
# ############################################################
# resource "azurerm_private_dns_zone" "mysql" {
#   name                = "privatelink.mysql.database.azure.com"
#   resource_group_name = azurerm_resource_group.rg.name
# }

# resource "azurerm_private_dns_zone_virtual_network_link" "mysql_vnet_link" {
#   name                  = "mysql-vnet-link"
#   resource_group_name   = azurerm_resource_group.rg.name
#   private_dns_zone_name = azurerm_private_dns_zone.mysql.name
#   virtual_network_id    = azurerm_virtual_network.vnet.id
# }

# ############################################################
# # Network Security Groups
# ############################################################
# resource "azurerm_network_security_group" "backend_nsg" {
#   name                = "backend-nsg"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name

#   security_rule {
#     name                       = "Allow-AppGateway"
#     priority                   = 100
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "3000"
#     source_address_prefix      = "10.0.1.0/24"
#     destination_address_prefix = "*"
#   }

#   security_rule {
#     name                       = "Allow-SSH-from-Bastion"
#     priority                   = 110
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "22"
#     source_address_prefix      = "10.0.4.0/27"
#     destination_address_prefix = "*"
#   }

#   security_rule {
#     name                       = "Deny-Internet-Inbound"
#     priority                   = 4096
#     direction                  = "Inbound"
#     access                     = "Deny"
#     protocol                   = "*"
#     source_port_range          = "*"
#     destination_port_range     = "*"
#     source_address_prefix      = "Internet"
#     destination_address_prefix = "*"
#   }
# }

# resource "azurerm_subnet_network_security_group_association" "backend_assoc" {
#   subnet_id                 = azurerm_subnet.backend.id
#   network_security_group_id = azurerm_network_security_group.backend_nsg.id
# }

# ############################################################
# # SSH Key
# ############################################################
# resource "tls_private_key" "vm_key" {
#   algorithm = "RSA"
#   rsa_bits  = 4096
# }

# resource "local_file" "ssh_private_key_file" {
#   content         = tls_private_key.vm_key.private_key_pem
#   filename        = "${path.module}/ssh_private_key.pem"
#   file_permission = "0600"
# }

# ############################################################
# # Managed MySQL Flexible Server
# ############################################################
# resource "random_string" "suffix" {
#   length  = 6
#   special = false
#   upper   = false
# }

# resource "azurerm_mysql_flexible_server" "db" {
#   name                   = "my3tier-db-${random_string.suffix.result}"
#   resource_group_name    = azurerm_resource_group.rg.name
#   location               = azurerm_resource_group.rg.location
#   version                = "8.0.21"
#   delegated_subnet_id    = azurerm_subnet.db.id
#   private_dns_zone_id    = azurerm_private_dns_zone.mysql.id
#   sku_name               = "GP_Standard_D2ds_v4"
#   administrator_login    = "mysqladmin"
#   administrator_password = "MyStrongPassword123!"
#   backup_retention_days  = 7
#   zone                   = "1"

#   depends_on = [
#     azurerm_private_dns_zone_virtual_network_link.mysql_vnet_link
#   ]
# }

# resource "azurerm_mysql_flexible_database" "mydb" {
#   name                = "mydb"
#   resource_group_name = azurerm_resource_group.rg.name
#   server_name         = azurerm_mysql_flexible_server.db.name
#   charset             = "utf8mb4"
#   collation           = "utf8mb4_unicode_ci"
# }

# ############################################################
# # Application Gateway (WAF_v2)
# ############################################################
# resource "azurerm_public_ip" "appgw_pip" {
#   name                = "appgw-public-ip"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   allocation_method   = "Static"
#   sku                 = "Standard"
# }

# resource "azurerm_application_gateway" "appgw" {
#   name                = "my3tier-appgateway"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name

#   sku {
#     name     = "WAF_v2"
#     tier     = "WAF_v2"
#     capacity = 2
#   }

#   gateway_ip_configuration {
#     name      = "appgw-ip-config"
#     subnet_id = azurerm_subnet.appgw.id
#   }

#   frontend_ip_configuration {
#     name                 = "appgw-frontend-ip"
#     public_ip_address_id = azurerm_public_ip.appgw_pip.id
#   }

#   frontend_port {
#     name = "frontend-port"
#     port = 80
#   }

#   backend_address_pool {
#     name = "backend-pool"

#   }

#   backend_http_settings {
#     name                  = "backend-http-settings"
#     cookie_based_affinity = "Disabled"
#     port                  = 3000
#     protocol              = "Http"
#     request_timeout       = 30
#     probe_name            = "backend-probe"
#   }

#   probe {
#     name                = "backend-probe"
#     protocol            = "Http"
#     path                = "/health" # Use a valid endpoint in your app
#     interval            = 15
#     timeout             = 10
#     unhealthy_threshold = 3
#   }

#   http_listener {
#     name                           = "http-listener"
#     frontend_ip_configuration_name = "appgw-frontend-ip"
#     frontend_port_name             = "frontend-port"
#     protocol                       = "Http"
#   }

#   request_routing_rule {
#     name                       = "http-rule"
#     rule_type                  = "Basic"
#     http_listener_name         = "http-listener"
#     backend_address_pool_name  = "backend-pool"
#     backend_http_settings_name = "backend-http-settings"
#     priority                   = 100
#   }

#   waf_configuration {
#     enabled          = true
#     firewall_mode    = "Detection"
#     rule_set_type    = "OWASP"
#     rule_set_version = "3.2"
#   }

#   tags = {
#     environment = "production"
#   }

#   depends_on = [azurerm_public_ip.appgw_pip]
# }

# ##################################################
# # KEY VAULT & SECRETS
# ##################################################
# data "azurerm_client_config" "current" {}

# resource "azurerm_key_vault" "kv" {
#   name                       = "my-app-key-vault"
#   location                   = azurerm_resource_group.rg.location
#   resource_group_name        = azurerm_resource_group.rg.name
#   sku_name                   = "standard"
#   tenant_id                  = data.azurerm_client_config.current.tenant_id
#   purge_protection_enabled   = true
#   soft_delete_retention_days = 7
# }

# locals {
#   app_secret_json = jsonencode({
#     DB_HOST     = azurerm_mysql_flexible_server.db.fqdn
#     DB_USER     = "mysqladmin"
#     DB_PASSWORD = "MyStrongPassword123!"
#     DB_NAME     = "mydb"
#   })
# }

# resource "azurerm_key_vault_secret" "app_secret" {
#   name         = "social-app-config"
#   value        = local.app_secret_json
#   key_vault_id = azurerm_key_vault.kv.id
#   depends_on   = [azurerm_mysql_flexible_server.db]
# }

# ##################################################
# # USER-ASSIGNED MANAGED IDENTITY & ACCESS POLICY
# ##################################################
# resource "azurerm_user_assigned_identity" "vmss_identity" {
#   name                = "vmss-identity"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
# }

# resource "azurerm_key_vault_access_policy" "vmss_policy" {
#   key_vault_id = azurerm_key_vault.kv.id
#   tenant_id    = data.azurerm_client_config.current.tenant_id
#   object_id    = azurerm_user_assigned_identity.vmss_identity.principal_id

#   secret_permissions = ["Get", "List"]
# }

# ############################################################
# # Backend VM Scale Set
# ############################################################
# resource "azurerm_linux_virtual_machine_scale_set" "backend_vmss" {
#   name                            = "backend-vmss"
#   location                        = azurerm_resource_group.rg.location
#   resource_group_name             = azurerm_resource_group.rg.name
#   sku                             = "Standard_B1ms"
#   instances                       = 2
#   admin_username                  = "azureuser"
#   disable_password_authentication = true
#   overprovision                   = true

#   identity {
#     type         = "UserAssigned"
#     identity_ids = [azurerm_user_assigned_identity.vmss_identity.id]
#   }

#   admin_ssh_key {
#     username   = "azureuser"
#     public_key = tls_private_key.vm_key.public_key_openssh
#   }

#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = "Standard_LRS"
#     disk_size_gb         = 30
#   }

#   network_interface {
#     name    = "backend-nic"
#     primary = true

#     ip_configuration {
#       name                                         = "backend-ipconfig"
#       subnet_id                                    = azurerm_subnet.backend.id
#       primary                                      = true
#       application_gateway_backend_address_pool_ids = [azurerm_application_gateway.appgw.backend_address_pool[0].id]
#     }
#   }

#   source_image_reference {
#     publisher = "Canonical"
#     offer     = "0001-com-ubuntu-server-focal"
#     sku       = "20_04-lts"
#     version   = "latest"
#   }

#   custom_data = base64encode(<<-EOF
# #!/bin/bash
# set -e
# apt-get update -y
# apt-get install -y curl git build-essential mysql-client
# curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
# apt-get install -y nodejs
# npm install -g pm2
# mkdir -p /home/azureuser/azure-3tier-app
# cd /home/azureuser/azure-3tier-app
# git clone https://github.com/ShamailAbbas/azure-3tier-app .
# chown -R azureuser:azureuser /home/azureuser/azure-3tier-app
# cd backend
# cat > .env <<'ENVEOF'
# KEY_VAULT_NAME=${azurerm_key_vault.kv.name}
# SECRET_NAME=${azurerm_key_vault_secret.app_secret.name}
# ENVEOF
# npm install
# runuser -l azureuser -c "pm2 start index.js --name myapp"
# runuser -l azureuser -c "pm2 save"
# systemctl enable pm2-azureuser
# systemctl start pm2-azureuser
# echo "Backend setup complete!"
# EOF
#   )

#   upgrade_mode = "Automatic"
#   depends_on   = [azurerm_application_gateway.appgw, azurerm_key_vault.kv]
# }

# ############################################################
# # Autoscale Configuration
# ############################################################
# resource "azurerm_monitor_autoscale_setting" "backend_autoscale" {
#   name                = "backend-autoscale"
#   resource_group_name = azurerm_resource_group.rg.name
#   location            = azurerm_resource_group.rg.location
#   target_resource_id  = azurerm_linux_virtual_machine_scale_set.backend_vmss.id
#   enabled             = true

#   profile {
#     name = "default-autoscale-profile"

#     capacity {
#       minimum = "2"
#       maximum = "5"
#       default = "2"
#     }

#     rule {
#       metric_trigger {
#         metric_name        = "Percentage CPU"
#         metric_resource_id = azurerm_linux_virtual_machine_scale_set.backend_vmss.id
#         time_grain         = "PT1M"
#         statistic          = "Average"
#         time_window        = "PT5M"
#         time_aggregation   = "Average"
#         operator           = "GreaterThan"
#         threshold          = 70
#       }

#       scale_action {
#         direction = "Increase"
#         type      = "ChangeCount"
#         value     = "1"
#         cooldown  = "PT5M"
#       }
#     }

#     rule {
#       metric_trigger {
#         metric_name        = "Percentage CPU"
#         metric_resource_id = azurerm_linux_virtual_machine_scale_set.backend_vmss.id
#         time_grain         = "PT1M"
#         statistic          = "Average"
#         time_window        = "PT10M"
#         time_aggregation   = "Average"
#         operator           = "LessThan"
#         threshold          = 30
#       }

#       scale_action {
#         direction = "Decrease"
#         type      = "ChangeCount"
#         value     = "1"
#         cooldown  = "PT10M"
#       }
#     }
#   }

#   depends_on = [azurerm_linux_virtual_machine_scale_set.backend_vmss]
# }

# ############################################################
# # Azure Bastion
# ############################################################
# resource "azurerm_public_ip" "bastion_pip" {
#   name                = "bastion-public-ip"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   allocation_method   = "Static"
#   sku                 = "Standard"
# }

# resource "azurerm_bastion_host" "bastion" {
#   name                = "my3tier-bastion"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name

#   ip_configuration {
#     name                 = "bastion-config"
#     subnet_id            = azurerm_subnet.bastion.id
#     public_ip_address_id = azurerm_public_ip.bastion_pip.id
#   }
# }

# ############################################################
# # Outputs
# ############################################################
# output "app_gateway_public_ip" {
#   value       = azurerm_public_ip.appgw_pip.ip_address
#   description = "Public IP of Azure Application Gateway"
# }
