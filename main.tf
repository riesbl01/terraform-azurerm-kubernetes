locals {
  cluster_name = "aks-${var.names.resource_group_type}-${var.names.product_name}-${var.names.environment}-${var.names.location}"
}

resource "azurerm_role_assignment" "subnet_network_contributor" {
  count                = (var.use_service_principal ? (var.aks_managed_vnet ? 0 : 1) : 0)
  scope                = var.default_node_pool_subnet.id
  role_definition_name = "Network Contributor"
  principal_id         = data.azuread_service_principal.aks[0].object_id
}

resource "azurerm_user_assigned_identity" "route_table_uai" {
  count               = var.aks_managed_vnet ? 0 : 1
  resource_group_name = var.resource_group_name
  location            = var.location

  name = "uai-${var.names.resource_group_type}-${var.names.product_name}-${var.names.environment}-${var.names.location}-route-table-rw"
}

resource "azurerm_role_assignment" "route_table_role_network_contributor" {
  count                = var.aks_managed_vnet ? 0 : 1
  scope                = var.route_table_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.route_table_uai[0].principal_id
}

resource "azurerm_kubernetes_cluster" "aks" {
  depends_on           = [azurerm_role_assignment.route_table_role_network_contributor]
  name                 = local.cluster_name
  location             = var.location
  resource_group_name  = var.resource_group_name
  dns_prefix           = "${var.names.product_name}-${var.names.environment}-${var.names.location}"
  tags                 = var.tags

  kubernetes_version = var.kubernetes_version

  network_profile {
    network_plugin       = var.network_plugin
  }

  default_node_pool {
    name                = var.default_node_pool_name
    vm_size             = var.default_node_pool_vm_size
    enable_auto_scaling = var.default_node_pool_enable_auto_scaling
    node_count          = (var.default_node_pool_enable_auto_scaling ? null : var.default_node_pool_node_count)
    min_count           = (var.default_node_pool_enable_auto_scaling ? var.default_node_pool_node_min_count : null)
    max_count           = (var.default_node_pool_enable_auto_scaling ? var.default_node_pool_node_max_count : null)
    availability_zones  = var.default_node_pool_availability_zones
    vnet_subnet_id      = (var.aks_managed_vnet ? null : var.default_node_pool_subnet.id)

    # disabled due to AKS bug
    #tags                = var.tags
  }

  addon_profile {
    kube_dashboard {
      enabled = var.enable_kube_dashboard
    }
  }

  dynamic "windows_profile" {
    for_each = var.enable_windows_node_pools ? [1] : []
    content {
      admin_username = var.windows_profile_admin_username
      admin_password = var.windows_profile_admin_password
    }
  }

  dynamic "identity" {
    for_each = var.use_service_principal ? [] : [1]
    content {
      type                      = var.aks_managed_vnet ? "SystemAssigned" : "UserAssigned"
      user_assigned_identity_id = var.aks_managed_vnet ? null : azurerm_user_assigned_identity.route_table_uai[0].id
    }
  }

  dynamic "service_principal" {
    for_each = var.use_service_principal ? [1] : []
    content {
      client_id     = var.service_principal_id
      client_secret = var.service_principal_secret
    }
  }
}

resource "azurerm_role_assignment" "acrpull_role" {
  for_each                         = var.acr_pull_access
  scope                            = each.value
  role_definition_name             = "AcrPull"
  principal_id                     = (var.use_service_principal ? data.azuread_service_principal.aks.0.id : azurerm_kubernetes_cluster.aks.kubelet_identity.0.object_id)
  skip_service_principal_aad_check = true
}
