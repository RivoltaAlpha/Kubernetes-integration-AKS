# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Virtual Network for AKS
resource "azurerm_virtual_network" "aks_vnet" {
  name                = "${var.aks_cluster_name}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "${var.aks_cluster_name}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = var.tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  name                = var.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main.id
  tags                = var.tags
}

# Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Premium"
  admin_enabled       = false
  
  georeplications {
    location = "westus"
    tags     = var.tags
  }

  network_rule_set {
    default_action = "Allow"
  }

  tags = var.tags
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.aks_dns_prefix
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "default"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    vnet_subnet_id      = azurerm_subnet.aks_subnet.id
    max_pods            = var.max_pods_per_node
    enable_auto_scaling = var.enable_auto_scaling
    min_count           = var.enable_auto_scaling ? var.min_node_count : null
    max_count           = var.enable_auto_scaling ? var.max_node_count : null
    type                = "VirtualMachineScaleSets"
    
    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = var.network_plugin
    network_policy     = var.network_policy
    load_balancer_sku  = "standard"
    outbound_type      = "loadBalancer"
    service_cidr       = "10.1.0.0/16"
    dns_service_ip     = "10.1.0.10"
  }

  # Enable Azure Monitor for containers
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # Enable Azure Policy
  azure_policy_enabled = var.enable_azure_policy

  # Enable managed identity for kubelet
  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.aks_identity.client_id
    object_id                 = azurerm_user_assigned_identity.aks_identity.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.aks_identity.id
  }

  # Auto-upgrade channel
  automatic_channel_upgrade = "stable"

  # Maintenance window
  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [2, 3, 4]
    }
  }

  tags = var.tags
}

# User Assigned Identity for AKS
resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = "${var.aks_cluster_name}-identity"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Role assignment for AKS to pull from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# Role assignment for network contributor
resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.aks_vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

# Diagnostic settings for AKS
resource "azurerm_monitor_diagnostic_setting" "aks_diagnostics" {
  name                       = "${var.aks_cluster_name}-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.aks.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
