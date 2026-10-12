# =============================================================================
# terraform/azure/main.tf
# Azure Infrastructure: Backup Vault, VM, Networking
# Author: Manicharan Ravi
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }
}

provider "azurerm" {
  features {
    recovery_services_vault {
      recover_soft_deleted_backup_protected_vm = true
    }
  }
}

variable "environment"   { default = "production" }
variable "location"      { default = "West Europe" }
variable "project_name"  { default = "myproject" }

# ── Resource Group ─────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
  tags     = { Environment = var.environment, ManagedBy = "Terraform" }
}

# ── Recovery Services Vault (Backup) ──────────────────────────────────────────
resource "azurerm_recovery_services_vault" "main" {
  name                = "rsv-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  soft_delete_enabled = true   # Protects against accidental deletion

  tags = { Environment = var.environment, ManagedBy = "Terraform" }
}

# ── Backup Policy — VM (Daily) ─────────────────────────────────────────────────
resource "azurerm_backup_policy_vm" "daily" {
  name                = "policy-vm-daily-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name

  backup {
    frequency = "Daily"
    time      = "02:00"
  }

  retention_daily {
    count = 30
  }

  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }

  retention_yearly {
    count    = 1
    weekdays = ["Sunday"]
    weeks    = ["First"]
    months   = ["January"]
  }
}

# ── Virtual Network ────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "private" {
  name                 = "snet-private"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ── Network Security Group ─────────────────────────────────────────────────────
resource "azurerm_network_security_group" "main" {
  name                = "nsg-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ── Key Vault (Secrets) ────────────────────────────────────────────────────────
resource "azurerm_key_vault" "main" {
  name                        = "kv-${var.project_name}-${var.environment}"
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 90
  purge_protection_enabled    = true
}

data "azurerm_client_config" "current" {}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "vault_name"     { value = azurerm_recovery_services_vault.main.name }
output "vault_id"       { value = azurerm_recovery_services_vault.main.id }
output "resource_group" { value = azurerm_resource_group.main.name }
