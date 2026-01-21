# Azure AKS Production Deployment Guide

## 📋 Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Infrastructure Setup with Terraform](#infrastructure-setup-with-terraform)
4. [Configure Jenkins for AKS Deployment](#configure-jenkins-for-aks-deployment)
5. [Deploy Application](#deploy-application)
6. [Monitoring and Observability](#monitoring-and-observability)
7. [Rollback Procedures](#rollback-procedures)
8. [Troubleshooting](#troubleshooting)

---

## Overview

This guide walks you through deploying your microservice application to **Azure Kubernetes Service (AKS)** with:

- ✅ **Terraform** for infrastructure as code
- ✅ **Production-ready configurations** (autoscaling, health checks, security)
- ✅ **Azure Monitor & Application Insights** for observability
- ✅ **Automated rollback** on deployment failures
- ✅ **Helm charts** for deployment management

---

## Prerequisites

### Required Tools
```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install kubectl
az aks install-cli

# Install Helm 3
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### Azure Account Setup
1. **Azure Subscription** with appropriate permissions
2. **Service Principal** for automation
3. **Resource Group** access

---

## Infrastructure Setup with Terraform

### Step 1: Configure Azure Backend for Terraform State

```bash
# Create resource group for Terraform state
az group create --name tfstate-rg --location eastus

# Create storage account for state files
az storage account create \
  --name tfstatemicroserviceapp \
  --resource-group tfstate-rg \
  --location eastus \
  --sku Standard_LRS

# Create storage container
az storage container create \
  --name tfstate \
  --account-name tfstatemicroserviceapp
```

### Step 2: Initialize Terraform

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan -out=tfplan

# Apply the configuration
terraform apply tfplan
```

### Step 3: Verify Infrastructure

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group microservice-app-prod-rg \
  --name microservice-app-aks

# Verify cluster access
kubectl get nodes
kubectl get namespaces
```

### What Terraform Creates

| Resource | Purpose |
|----------|---------|
| **AKS Cluster** | Kubernetes cluster with 3-10 auto-scaling nodes |
| **Azure Container Registry (ACR)** | Private container registry with geo-replication |
| **Log Analytics Workspace** | Centralized logging for all AKS resources |
| **Application Insights** | Application performance monitoring |
| **Azure Monitor Workspace** | Managed Prometheus metrics |
| **Virtual Network** | Isolated network for AKS |
| **Monitoring Alerts** | CPU, memory, and pod failure alerts |

---

## Configure Jenkins for AKS Deployment

### Step 1: Create Azure Service Principal

```bash
# Create service principal
az ad sp create-for-rbac \
  --name "jenkins-aks-deployer" \
  --role contributor \
  --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID>

# Output will contain:
# {
#   "appId": "<CLIENT_ID>",
#   "password": "<CLIENT_SECRET>",
#   "tenant": "<TENANT_ID>"
# }
```

### Step 2: Add Credentials to Jenkins

Navigate to **Jenkins → Manage Jenkins → Credentials → Global → Add Credentials**

1. **Azure Service Principal**
   - Type: `Username with password`
   - ID: `azure-service-principal`
   - Username: `<CLIENT_ID from above>`
   - Password: `<CLIENT_SECRET from above>`

2. **Azure Tenant ID**
   - Type: `Secret text`
   - ID: `azure-tenant-id`
   - Secret: `<TENANT_ID from above>`

3. **Azure Subscription ID**
   - Type: `Secret text`
   - ID: `azure-subscription-id`
   - Secret: `<YOUR_SUBSCRIPTION_ID>`

### Step 3: Install Required Jenkins Plugins

Install these plugins via **Manage Jenkins → Plugin Manager**:
- Azure Credentials
- Kubernetes CLI
- Pipeline

### Step 4: Install Azure CLI and Helm in Jenkins Container

```bash
# Exec into Jenkins container
docker exec -it jenkins bash

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install kubectl
az aks install-cli

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installations
az --version
kubectl version --client
helm version
```

---

## Deploy Application

### Option 1: Deploy via Jenkins Pipeline (Recommended)

1. **Push to `prod` branch**:
   ```bash
   git checkout prod
   git merge main
   git push origin prod
   ```

2. **Jenkins will automatically**:
   - Build application
   - Run tests and security scans
   - Build Docker image
   - Push to Azure Container Registry
   - Deploy to AKS using Helm
   - Run smoke tests
   - Auto-rollback on failure

### Option 2: Manual Deployment via Helm

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group microservice-app-prod-rg \
  --name microservice-app-aks

# Install Application Insights secret
INSTRUMENTATION_KEY=$(az monitor app-insights component show \
  --app microservice-app-insights \
  --resource-group microservice-app-prod-rg \
  --query instrumentationKey -o tsv)

kubectl create secret generic app-insights-key \
  --namespace=production \
  --from-literal=instrumentationKey="$INSTRUMENTATION_KEY"

# Deploy with Helm
helm upgrade microservice-app ./helm/microservice-app \
  --install \
  --namespace production \
  --create-namespace \
  --set image.repository=microserviceappacr.azurecr.io/microservice-app \
  --set image.tag=prod-1.0.0 \
  --wait \
  --timeout 5m
```

### Option 3: Manual Deployment via Kubectl

```bash
# Apply Kubernetes manifests
kubectl apply -f k8s/production/namespace.yaml
kubectl apply -f k8s/production/configmap.yaml
kubectl apply -f k8s/production/rbac.yaml
kubectl apply -f k8s/production/deployment.yaml
kubectl apply -f k8s/production/service.yaml
kubectl apply -f k8s/production/hpa.yaml
kubectl apply -f k8s/production/pdb.yaml

# Check deployment status
kubectl rollout status deployment/microservice-app -n production
```

---

## Monitoring and Observability

### Azure Monitor Container Insights

**Access**: Azure Portal → AKS Cluster → Monitoring → Insights

**Key Metrics**:
- Node CPU/Memory utilization
- Pod status and restarts
- Container logs
- Resource consumption

### Application Insights

**Access**: Azure Portal → Application Insights → microservice-app-insights

**Features**:
- Request rates and response times
- Failed requests
- Dependencies
- Live metrics
- Distributed tracing

### Custom Queries in Log Analytics

```kusto
// Failed pods in last 24 hours
KubePodInventory
| where TimeGenerated > ago(24h)
| where PodStatus == "Failed"
| project TimeGenerated, Namespace, Name, PodStatus

// Container restarts
KubePodInventory
| where RestartCount > 0
| summarize RestartCount=max(RestartCount) by Name, Namespace
| order by RestartCount desc

// Application errors
ContainerLog
| where LogEntry contains "error" or LogEntry contains "Error"
| where Namespace == "production"
| project TimeGenerated, ContainerID, LogEntry
| take 100
```

### Access Application Logs

```bash
# View logs from all pods
kubectl logs -n production -l app=microservice-app --tail=100

# Stream logs in real-time
kubectl logs -n production -l app=microservice-app -f

# View specific pod logs
kubectl logs -n production <POD_NAME>

# View previous container logs (if pod crashed)
kubectl logs -n production <POD_NAME> --previous
```

### Prometheus Metrics

Metrics are automatically collected by Azure Monitor Managed Prometheus.

**Access**: Azure Portal → Monitor → Workspaces → microservice-app-prometheus

**Key Metrics**:
- `container_cpu_usage_seconds_total`
- `container_memory_working_set_bytes`
- `kube_pod_status_phase`
- Custom application metrics from `/metrics` endpoint

### Setup Monitoring Script

Run the provided script to configure monitoring:

```bash
chmod +x scripts/setup-monitoring.sh
export RESOURCE_GROUP="microservice-app-prod-rg"
export CLUSTER_NAME="microservice-app-aks"
./scripts/setup-monitoring.sh
```

---

## Rollback Procedures

### Automatic Rollback

The Jenkins pipeline includes **automatic rollback** on deployment failure using Helm's `--atomic` flag.

If deployment fails:
1. Helm automatically rolls back to the previous working revision
2. Jenkins logs show rollback status
3. Previous version continues serving traffic

### Manual Rollback via Helm

```bash
# View deployment history
helm history microservice-app -n production

# Rollback to previous revision
helm rollback microservice-app -n production

# Rollback to specific revision
helm rollback microservice-app 3 -n production

# Verify rollback
kubectl get pods -n production -l app=microservice-app
```

### Manual Rollback via Kubectl

```bash
# View deployment history
kubectl rollout history deployment/microservice-app -n production

# Rollback to previous version
kubectl rollout undo deployment/microservice-app -n production

# Rollback to specific revision
kubectl rollout undo deployment/microservice-app -n production --to-revision=3

# Monitor rollback progress
kubectl rollout status deployment/microservice-app -n production
```

### Using Rollback Script

```bash
chmod +x scripts/rollback.sh

# Rollback to previous version
export NAMESPACE="production"
export RELEASE_NAME="microservice-app"
./scripts/rollback.sh

# Rollback to specific revision
export REVISION=3
./scripts/rollback.sh
```

### Rollback Verification

After rollback, verify:

```bash
# Check pod status
kubectl get pods -n production -l app=microservice-app

# Check deployment revision
helm list -n production
kubectl rollout history deployment/microservice-app -n production

# Test health endpoint
EXTERNAL_IP=$(kubectl get svc microservice-app -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$EXTERNAL_IP/health
```

---

## Troubleshooting

### Pods Not Starting

```bash
# Describe pod to see events
kubectl describe pod <POD_NAME> -n production

# Check pod logs
kubectl logs <POD_NAME> -n production

# Check if image can be pulled
kubectl get events -n production --sort-by='.lastTimestamp'
```

**Common Issues**:
- Image pull errors → Check ACR permissions
- CrashLoopBackOff → Check application logs
- Pending → Check node resources

### Image Pull Errors

```bash
# Verify ACR integration
az aks check-acr \
  --resource-group microservice-app-prod-rg \
  --name microservice-app-aks \
  --acr microserviceappacr.azurecr.io

# Recreate ACR role assignment
az aks update \
  --resource-group microservice-app-prod-rg \
  --name microservice-app-aks \
  --attach-acr microserviceappacr
```

### Application Not Accessible

```bash
# Check service status
kubectl get svc -n production

# Check if external IP is assigned
kubectl describe svc microservice-app -n production

# Check network policies
kubectl get networkpolicy -n production
```

### High Resource Usage

```bash
# Check resource usage
kubectl top nodes
kubectl top pods -n production

# Scale deployment manually
kubectl scale deployment microservice-app -n production --replicas=5

# Check HPA status
kubectl get hpa -n production
kubectl describe hpa microservice-app-hpa -n production
```

### Deployment Stuck

```bash
# Check deployment status
kubectl rollout status deployment/microservice-app -n production

# Pause rollout
kubectl rollout pause deployment/microservice-app -n production

# Resume rollout
kubectl rollout resume deployment/microservice-app -n production

# Force restart
kubectl rollout restart deployment/microservice-app -n production
```

### View Azure Monitor Logs

```bash
# Install Azure CLI Log Analytics extension
az extension add --name log-analytics

# Query logs
az monitor log-analytics query \
  --workspace <WORKSPACE_ID> \
  --analytics-query "ContainerLog | where Namespace == 'production' | take 100"
```

---

## Production Checklist

Before going live, ensure:

- [ ] Terraform infrastructure applied successfully
- [ ] AKS cluster is healthy (`kubectl get nodes`)
- [ ] Application Insights configured
- [ ] Azure Monitor alerts configured
- [ ] Jenkins credentials configured
- [ ] Successful test deployment
- [ ] Health checks responding (`/health`, `/ready`)
- [ ] External IP accessible
- [ ] SSL/TLS configured (if needed)
- [ ] Backup and disaster recovery plan
- [ ] Rollback tested
- [ ] Monitoring dashboards configured
- [ ] On-call procedures documented

---

## Useful Commands Reference

```bash
# Get AKS credentials
az aks get-credentials --resource-group microservice-app-prod-rg --name microservice-app-aks

# View all resources in production namespace
kubectl get all -n production

# Port forward to test locally
kubectl port-forward -n production svc/microservice-app 8080:80

# Execute commands in pod
kubectl exec -it -n production <POD_NAME> -- /bin/sh

# View cluster info
kubectl cluster-info
kubectl get nodes -o wide

# View Helm releases
helm list -n production

# Update Helm chart
helm upgrade microservice-app ./helm/microservice-app -n production

# Delete deployment
helm uninstall microservice-app -n production
```

---

## Additional Resources

- [Azure AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [Application Insights for Node.js](https://docs.microsoft.com/en-us/azure/azure-monitor/app/nodejs)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

## Support

For issues or questions:
1. Check Jenkins build logs
2. Check Kubernetes events and pod logs
3. Review Azure Monitor and Application Insights
4. Contact DevOps team

