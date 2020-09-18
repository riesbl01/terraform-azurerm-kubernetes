data "azuread_service_principal" "aks" {
  count        = (var.use_service_principal ? 1 : 0)
  application_id = var.service_principal_id
}

data "azurerm_public_ip" "outbound_ips" {
  for_each = toset(azurerm_kubernetes_cluster.aks.network_profile[0].load_balancer_profile[0].effective_outbound_ips)
  name                = reverse(split("/", each.key))[0]
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group
}
