variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "production"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
  default     = "microservice-app-prod-rg"
}

variable "aks_cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "microservice-app-aks"
}

variable "aks_dns_prefix" {
  description = "DNS prefix for AKS cluster"
  type        = string
  default     = "microserviceapp"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28.3"
}

variable "node_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 3
}

variable "node_vm_size" {
  description = "VM size for nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "max_pods_per_node" {
  description = "Maximum number of pods per node"
  type        = number
  default     = 110
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for node pool"
  type        = bool
  default     = true
}

variable "min_node_count" {
  description = "Minimum number of nodes when auto-scaling"
  type        = number
  default     = 2
}

variable "max_node_count" {
  description = "Maximum number of nodes when auto-scaling"
  type        = number
  default     = 10
}

variable "acr_name" {
  description = "Azure Container Registry name"
  type        = string
  default     = "microserviceappacr"
}

variable "log_analytics_workspace_name" {
  description = "Log Analytics Workspace name"
  type        = string
  default     = "microservice-app-logs"
}

variable "app_insights_name" {
  description = "Application Insights name"
  type        = string
  default     = "microservice-app-insights"
}

variable "enable_monitoring" {
  description = "Enable Azure Monitor for containers"
  type        = bool
  default     = true
}

variable "enable_azure_policy" {
  description = "Enable Azure Policy for AKS"
  type        = bool
  default     = true
}

variable "network_plugin" {
  description = "Network plugin (azure or kubenet)"
  type        = string
  default     = "azure"
}

variable "network_policy" {
  description = "Network policy (azure or calico)"
  type        = string
  default     = "azure"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Application = "MicroserviceApp"
  }
}
