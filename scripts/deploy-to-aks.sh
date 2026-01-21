#!/bin/bash

# Complete AKS deployment script
# This script automates the entire deployment process

set -e

echo "🚀 Starting AKS Deployment Process"
echo "===================================="

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-microservice-app-prod-rg}"
CLUSTER_NAME="${CLUSTER_NAME:-microservice-app-aks}"
ACR_NAME="${ACR_NAME:-microserviceappacr}"
NAMESPACE="${NAMESPACE:-production}"
HELM_RELEASE="${HELM_RELEASE:-microservice-app}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Step 1: Verify prerequisites
echo ""
echo "📋 Step 1: Verifying prerequisites..."
command -v az >/dev/null 2>&1 || { echo "❌ Azure CLI is required but not installed."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ Helm is required but not installed."; exit 1; }
echo "✅ All prerequisites installed"

# Step 2: Login to Azure
echo ""
echo "🔐 Step 2: Logging in to Azure..."
az account show >/dev/null 2>&1 || az login
echo "✅ Logged in to Azure"

# Step 3: Set subscription
echo ""
echo "📌 Step 3: Setting Azure subscription..."
if [ -n "$AZURE_SUBSCRIPTION_ID" ]; then
    az account set --subscription "$AZURE_SUBSCRIPTION_ID"
    echo "✅ Subscription set to: $AZURE_SUBSCRIPTION_ID"
else
    echo "ℹ️  Using default subscription: $(az account show --query name -o tsv)"
fi

# Step 4: Deploy Terraform infrastructure (if not exists)
echo ""
echo "🏗️  Step 4: Checking Terraform infrastructure..."
if [ -d "terraform" ]; then
    read -p "Do you want to deploy/update Terraform infrastructure? (yes/no): " DEPLOY_TF
    if [ "$DEPLOY_TF" == "yes" ]; then
        cd terraform
        terraform init
        terraform plan -out=tfplan
        terraform apply tfplan
        cd ..
        echo "✅ Terraform infrastructure deployed"
    else
        echo "⏭️  Skipping Terraform deployment"
    fi
else
    echo "⚠️  Terraform directory not found, skipping infrastructure setup"
fi

# Step 5: Get AKS credentials
echo ""
echo "🔑 Step 5: Getting AKS credentials..."
az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --overwrite-existing
echo "✅ AKS credentials configured"

# Step 6: Verify cluster access
echo ""
echo "🔍 Step 6: Verifying cluster access..."
kubectl cluster-info
kubectl get nodes
echo "✅ Cluster access verified"

# Step 7: Create namespace
echo ""
echo "📦 Step 7: Creating namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Namespace created/verified"

# Step 8: Setup Application Insights secret
echo ""
echo "🔐 Step 8: Setting up Application Insights..."
INSTRUMENTATION_KEY=$(az monitor app-insights component show \
    --app microservice-app-insights \
    --resource-group "$RESOURCE_GROUP" \
    --query instrumentationKey -o tsv 2>/dev/null || echo "")

if [ -n "$INSTRUMENTATION_KEY" ]; then
    CONNECTION_STRING=$(az monitor app-insights component show \
        --app microservice-app-insights \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString -o tsv)
    
    kubectl create secret generic app-insights-key \
        --namespace="$NAMESPACE" \
        --from-literal=instrumentationKey="$INSTRUMENTATION_KEY" \
        --from-literal=connectionString="$CONNECTION_STRING" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    echo "✅ Application Insights secret configured"
else
    echo "⚠️  Application Insights not found, skipping secret creation"
fi

# Step 9: Login to ACR
echo ""
echo "🐳 Step 9: Logging in to Azure Container Registry..."
az acr login --name "$ACR_NAME"
echo "✅ Logged in to ACR"

# Step 10: Deploy application with Helm
echo ""
echo "🚀 Step 10: Deploying application with Helm..."
helm upgrade "$HELM_RELEASE" ./helm/microservice-app \
    --install \
    --namespace "$NAMESPACE" \
    --set image.repository="$ACR_NAME.azurecr.io/microservice-app" \
    --set image.tag="$IMAGE_TAG" \
    --wait \
    --timeout 5m \
    --atomic
echo "✅ Application deployed successfully"

# Step 11: Verify deployment
echo ""
echo "✅ Step 11: Verifying deployment..."
kubectl rollout status deployment/"$HELM_RELEASE" -n "$NAMESPACE" --timeout=5m
kubectl get pods,svc,deployment -n "$NAMESPACE" -l app=microservice-app

# Step 12: Get service endpoint
echo ""
echo "🌐 Step 12: Getting service endpoint..."
echo "Waiting for external IP (this may take a few minutes)..."
for i in {1..30}; do
    EXTERNAL_IP=$(kubectl get svc "$HELM_RELEASE" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$EXTERNAL_IP" ]; then
        echo "✅ External IP: $EXTERNAL_IP"
        echo ""
        echo "🧪 Testing health endpoint..."
        sleep 10  # Wait a bit for the service to be fully ready
        curl -f "http://$EXTERNAL_IP/health" && echo "" || echo "⚠️  Health check not ready yet"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 10
done

# Final summary
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         🎉 DEPLOYMENT COMPLETED SUCCESSFULLY 🎉           ║"
echo "╠═══════════════════════════════════════════════════════════╣"
echo "║ Cluster:     $CLUSTER_NAME"
echo "║ Namespace:   $NAMESPACE"
echo "║ Release:     $HELM_RELEASE"
echo "║ Image:       $ACR_NAME.azurecr.io/microservice-app:$IMAGE_TAG"
if [ -n "$EXTERNAL_IP" ]; then
echo "║ Endpoint:    http://$EXTERNAL_IP"
fi
echo "║"
echo "║ Next steps:"
echo "║ - View logs: kubectl logs -n $NAMESPACE -l app=microservice-app"
echo "║ - Monitor:   Azure Portal → Application Insights"
echo "║ - Scale:     kubectl scale deployment $HELM_RELEASE -n $NAMESPACE --replicas=5"
echo "║ - Rollback:  helm rollback $HELM_RELEASE -n $NAMESPACE"
echo "╚═══════════════════════════════════════════════════════════╝"
