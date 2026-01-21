#!/bin/bash

# Deploy Azure Monitor and Application Insights integration for AKS
# This script sets up complete observability for the AKS cluster

set -e

RESOURCE_GROUP="${RESOURCE_GROUP:-microservice-app-prod-rg}"
CLUSTER_NAME="${CLUSTER_NAME:-microservice-app-aks}"
LOCATION="${LOCATION:-eastus}"
WORKSPACE_NAME="${WORKSPACE_NAME:-microservice-app-logs}"
APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-microservice-app-insights}"

echo "🔧 Setting up Azure Monitor and Application Insights..."

# 1. Get AKS credentials
echo "📦 Getting AKS credentials..."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --overwrite-existing

# 2. Enable Container Insights (if not already enabled)
echo "📊 Enabling Container Insights..."
az aks enable-addons \
  --addons monitoring \
  --name "$CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME" \
  || echo "Container Insights already enabled"

# 3. Get Application Insights instrumentation key
echo "🔑 Retrieving Application Insights keys..."
INSTRUMENTATION_KEY=$(az monitor app-insights component show \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query instrumentationKey -o tsv)

CONNECTION_STRING=$(az monitor app-insights component show \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query connectionString -o tsv)

# 4. Create Kubernetes secret for Application Insights
echo "🔐 Creating Application Insights secret in Kubernetes..."
kubectl create secret generic app-insights-key \
  --namespace=production \
  --from-literal=instrumentationKey="$INSTRUMENTATION_KEY" \
  --from-literal=connectionString="$CONNECTION_STRING" \
  --dry-run=client -o yaml | kubectl apply -f -

# 5. Install Azure Monitor Managed Prometheus (optional - for advanced metrics)
echo "📈 Enabling Azure Monitor Managed Prometheus..."
az aks update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --enable-azure-monitor-metrics \
  || echo "Azure Monitor Metrics already enabled"

# 6. Create Log Analytics queries for common scenarios
echo "📝 Creating saved queries in Log Analytics..."

# Query 1: Failed pods
az monitor log-analytics workspace saved-search create \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$WORKSPACE_NAME" \
  --name "FailedPods" \
  --category "Kubernetes" \
  --query "KubePodInventory | where PodStatus == 'Failed' | project TimeGenerated, Namespace, Name, PodStatus, ContainerStatus" \
  --display-name "Failed Pods" \
  || echo "Query already exists"

# Query 2: Container restarts
az monitor log-analytics workspace saved-search create \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$WORKSPACE_NAME" \
  --name "ContainerRestarts" \
  --category "Kubernetes" \
  --query "KubePodInventory | where RestartCount > 0 | summarize RestartCount=max(RestartCount) by Name, Namespace | order by RestartCount desc" \
  --display-name "Container Restarts" \
  || echo "Query already exists"

# Query 3: Application errors
az monitor log-analytics workspace saved-search create \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$WORKSPACE_NAME" \
  --name "ApplicationErrors" \
  --category "Application" \
  --query "ContainerLog | where LogEntry contains 'error' or LogEntry contains 'Error' or LogEntry contains 'ERROR' | project TimeGenerated, Computer, ContainerID, LogEntry" \
  --display-name "Application Errors" \
  || echo "Query already exists"

echo "✅ Azure Monitor and Application Insights setup complete!"
echo ""
echo "📊 Access your dashboards:"
echo "  Log Analytics: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME"
echo "  Application Insights: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/components/$APP_INSIGHTS_NAME"
echo ""
echo "🔑 Instrumentation Key: $INSTRUMENTATION_KEY"
