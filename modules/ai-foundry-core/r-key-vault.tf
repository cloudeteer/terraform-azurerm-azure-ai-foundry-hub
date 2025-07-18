locals {
  key_vault_name = format(
    "kv%s%s",
    lower(
      substr(
        replace(var.basename, "-", ""), 0, 24 - 2 - local.random_string_length
      )
    ),
    random_string.suffix.result
  )
}

#trivy:ignore:avd-azu-0013 // Key vault should have the network acl block specified
#trivy:ignore:avd-azu-0016 // Key vault should have purge protection enabled
resource "azurerm_key_vault" "this" {
  name                = local.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = "standard"

  purge_protection_enabled      = true
  public_network_access_enabled = var.public_network_access
  enable_rbac_authorization     = true

  network_acls {
    bypass         = length(var.allowed_ips) > 0 ? "AzureServices" : "None"
    default_action = length(var.allowed_ips) > 0 ? "Deny" : "Allow"
    ip_rules       = var.allowed_ips
  }
}
