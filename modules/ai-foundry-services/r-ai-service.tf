resource "random_string" "identifier" {
  length  = 8
  upper   = false
  special = false
}

resource "azurerm_ai_services" "this" {
  name                = "ais-${var.basename}"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku_name              = var.sku
  custom_subdomain_name = "${var.basename}-${lower(random_string.identifier.result)}"

  local_authentication_enabled = var.local_authentication_enabled

  public_network_access              = "Enabled" # Allow Selected Networks and Private Endpoints
  outbound_network_access_restricted = true

  network_acls {
    default_action = length(var.allowed_ips) > 0 ? "Deny" : "Allow"
    ip_rules       = var.allowed_ips
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azapi_resource" "ai_services_connection_hub" {
  type      = "Microsoft.MachineLearningServices/workspaces/connections@2024-10-01-preview"
  name      = "aisc-${var.basename}"
  parent_id = var.hub_id

  response_export_values = ["*"]

  body = {
    properties = {
      category      = "AIServices",
      target        = azurerm_ai_services.this.endpoint,
      authType      = "AAD",
      isSharedToAll = true,
      metadata = {
        ApiType    = "Azure",
        ResourceId = azurerm_ai_services.this.id
      }
    }
  }

  # Explicit dependency: Creating the connection resource in parallel with the outbound rule can cause intermittent
  # 'InternalServerError' or 'ServiceError' responses from the Azure API. Adding this dependency ensures the outbound
  # rule is fully provisioned before the connection is created, preventing these errors.
  depends_on = [azapi_resource.ai_services_outbound_rule_hub]
}

resource "azapi_resource" "ai_services_outbound_rule_hub" {
  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "pe-${azurerm_ai_services.this.name}"
  parent_id = var.hub_id

  response_export_values = ["*"]

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = azurerm_ai_services.this.id
        subresourceTarget = "account"
      }
    }
  }
}

resource "azurerm_role_assignment" "ai_service_developer" {
  for_each = var.ai_developer_principal_id == null ? [] : toset([
    "Cognitive Services Contributor",
    "Cognitive Services OpenAI Contributor",
    "Cognitive Services User",
  ])

  principal_id         = var.ai_developer_principal_id
  role_definition_name = each.value
  scope                = azurerm_ai_services.this.id
}

resource "azurerm_role_assignment" "ai_service_developer_user_access_administrator" {
  count = var.ai_developer_principal_id == null ? 0 : 1

  description          = "This role assignment is needed to deploy web apps from ai.azure.com"
  principal_id         = var.ai_developer_principal_id
  role_definition_name = "User Access Administrator"
  scope                = azurerm_ai_services.this.id

  condition_version = "2.0"
  condition         = <<-CONDITION
    (
        (
          !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
        )
        OR
        (
          @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {5e0bd9bd-7b93-4f28-af87-19fc36ad61bd}
        )
    )
    AND
    (
        (
          !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
        )
        OR
        (
          @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {5e0bd9bd-7b93-4f28-af87-19fc36ad61bd}
        )
    )
  CONDITION
}

resource "azurerm_role_assignment" "ai_service_search_service" {
  for_each = var.create_rbac ? toset([
    "Cognitive Services OpenAI Contributor",
  ]) : []

  principal_id         = azurerm_search_service.this.identity[0].principal_id
  role_definition_name = each.value
  scope                = azurerm_ai_services.this.id
}

resource "azurerm_role_assignment" "storage_account_ai_service" {
  for_each = var.create_rbac ? toset([
    "Storage Blob Data Contributor",
  ]) : []

  principal_id         = azurerm_ai_services.this.identity[0].principal_id
  role_definition_name = each.value
  scope                = var.storage_account_id
}
