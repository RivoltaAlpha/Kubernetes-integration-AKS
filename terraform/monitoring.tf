# Azure Monitor Workspace for Prometheus
resource "azurerm_monitor_workspace" "prometheus" {
  name                = "${var.aks_cluster_name}-prometheus"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Enable Prometheus metrics collection on AKS
resource "azurerm_monitor_data_collection_endpoint" "aks" {
  name                = "${var.aks_cluster_name}-dce"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "Linux"
  tags                = var.tags
}

resource "azurerm_monitor_data_collection_rule" "aks" {
  name                        = "${var.aks_cluster_name}-dcr"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.aks.id

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
      name                  = "log-analytics"
    }

    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.prometheus.id
      name               = "prometheus"
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerLogV2"]
    destinations = ["log-analytics"]
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["prometheus"]
  }

  data_sources {
    extension {
      extension_name = "ContainerInsights"
      name           = "ContainerInsightsExtension"
      streams        = ["Microsoft-ContainerLogV2"]
    }

    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }

  tags = var.tags
}

# Associate DCR with AKS cluster
resource "azurerm_monitor_data_collection_rule_association" "aks" {
  name                    = "${var.aks_cluster_name}-dcra"
  target_resource_id      = azurerm_kubernetes_cluster.aks.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.aks.id
}

# Action Group for alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "${var.aks_cluster_name}-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "aks-alerts"

  email_receiver {
    name                    = "devops-team"
    email_address           = "devops@example.com"
    use_common_alert_schema = true
  }

  # Add webhook for Slack, PagerDuty, etc.
  webhook_receiver {
    name        = "slack-webhook"
    service_uri = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
  }

  tags = var.tags
}

# Metric alerts for AKS
resource "azurerm_monitor_metric_alert" "node_cpu" {
  name                = "${var.aks_cluster_name}-high-node-cpu"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_kubernetes_cluster.aks.id]
  description         = "Alert when node CPU usage is high"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "node_memory" {
  name                = "${var.aks_cluster_name}-high-node-memory"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_kubernetes_cluster.aks.id]
  description         = "Alert when node memory usage is high"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_memory_working_set_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "pod_failed" {
  name                = "${var.aks_cluster_name}-pod-failed"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_kubernetes_cluster.aks.id]
  description         = "Alert when pods are in failed state"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "kube_pod_status_phase"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "phase"
      operator = "Include"
      values   = ["Failed"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = var.tags
}
