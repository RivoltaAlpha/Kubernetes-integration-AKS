# Terraform Quick Reference

## Initial Setup

```bash
# 1. Create backend storage
az group create --name tfstate-rg --location eastus
az storage account create --name tfstatemicroserviceapp --resource-group tfstate-rg --location eastus --sku Standard_LRS
az storage container create --name tfstate --account-name tfstatemicroserviceapp

# 2. Login to Azure
az login

# 3. Set subscription
az account set --subscription <YOUR_SUBSCRIPTION_ID>

# 4. Initialize Terraform
cd terraform
terraform init

# 5. Create workspace (optional)
terraform workspace new production
terraform workspace select production
```

## Common Commands

```bash
# Plan changes
terraform plan

# Apply changes
terraform apply

# Destroy infrastructure
terraform destroy

# View current state
terraform show

# List resources
terraform state list

# Format files
terraform fmt -recursive

# Validate configuration
terraform validate
```

## Variables Override

Create `terraform.tfvars` file:

```hcl
environment         = "production"
location           = "eastus"
resource_group_name = "my-custom-rg"
node_count         = 5
node_vm_size       = "Standard_D4s_v3"
```

## Outputs

```bash
# View all outputs
terraform output

# View specific output
terraform output aks_cluster_name
terraform output acr_login_server

# Get kubeconfig command
terraform output -raw get_credentials_command
```

## Troubleshooting

```bash
# Refresh state
terraform refresh

# Taint resource (force recreate)
terraform taint azurerm_kubernetes_cluster.aks

# Import existing resource
terraform import azurerm_resource_group.main /subscriptions/<SUB_ID>/resourceGroups/<RG_NAME>
```
