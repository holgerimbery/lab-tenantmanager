# Deployment

## Prerequisites

- Azure CLI ≥ 2.60 with Bicep: `az bicep install`
- Azure subscription (Contributor on target resource group)
- Completed [App Registration](App-Registration.md) — you need `clientId` and `clientSecret`
- Your Entra ID Object ID:

```bash
az ad signed-in-user show --query id -o tsv
```

## Option A — Deploy to Azure Button

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fholgerimbery%2Flab-tenantmanager%2Fmain%2Fdeploy%2Fazuredeploy.json)

The portal wizard will ask for:
- **Subscription** and **Resource Group** (create new or use existing)
- **baseName** — 3–16 lowercase alphanumeric characters, prefix for all resource names
- **location** — Azure region (defaults to resource group location)
- **kvAdminObjectId** — your Entra ID Object ID (from the command above)

## Option B — Azure CLI

```bash
RESOURCE_GROUP=rg-lab-tenant-manager
LOCATION=northeurope         # change to your preferred region
BASE_NAME=ltm                # 3–16 lowercase alphanumeric
KV_ADMIN_OID=<your-object-id>

# Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Deploy infrastructure
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-uri https://raw.githubusercontent.com/holgerimbery/lab-tenantmanager/main/deploy/azuredeploy.json \
  --parameters \
      baseName=$BASE_NAME \
      kvAdminObjectId=$KV_ADMIN_OID
```

Note the deployment outputs — you will need them in the next step:

```bash
az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name azuredeploy \
  --query properties.outputs
```

| Output | Description |
|--------|-------------|
| `appUrl` | Container App FQDN — use this as `NEXTAUTH_URL` |
| `containerAppName` | Container App resource name |
| `acrLoginServer` | ACR login server (used by CI/CD) |
| `cosmosAccountName` | Cosmos DB account name |
| `keyVaultName` | Key Vault resource name |

## Resources Created

| Resource | Name pattern | Notes |
|----------|-------------|-------|
| Container App | `ca-<baseName>` | `minReplicas: 1` |
| Container Apps Environment | `cae-<baseName>` | |
| Cosmos DB account | `cosmos-<baseName>-…` | Serverless; container `lab-data`, partition `/tenantId` |
| Key Vault | `kv-<baseName>-…` | Stores `tenant-{tenantId}-refresh-token` secrets |
| Container Registry (ACR) | `acr<baseName>…` | Private; CI pushes image here |

## Configure the Container App

After deployment, set environment variables and secrets:

```bash
CA=ca-ltm          # from deployment output: containerAppName
RG=rg-lab-tenant-manager

# Secrets
az containerapp secret set -n $CA -g $RG --secrets \
  "ad-client-secret=<your-client-secret>" \
  "nextauth-secret=$(openssl rand -base64 32)" \
  "auth-secret=$(openssl rand -base64 32)"

# Non-secret environment variables
az containerapp update -n $CA -g $RG --set-env-vars \
  "AZURE_AD_CLIENT_ID=<app-registration-client-id>" \
  "OPERATOR_TENANT_ID=<your-operator-tenant-id>" \
  "NEXTAUTH_URL=https://<your-container-app-fqdn>" \
  "MAIL_SENDER_UPN=noreply@yourdomain.com" \
  "PP_DEFAULT_REGION=europe" \
  "PP_DEFAULT_CURRENCY=EUR" \
  "PP_DEFAULT_LANGUAGE=1033" \
  "USAGE_LOCATION=DE"

# Wire secrets into env vars
az containerapp update -n $CA -g $RG --set-env-vars \
  "AZURE_AD_CLIENT_SECRET=secretref:ad-client-secret" \
  "NEXTAUTH_SECRET=secretref:nextauth-secret" \
  "AUTH_SECRET=secretref:auth-secret"
```

See [Configuration Reference](Configuration-Reference.md) for all available variables.

## Add Redirect URIs

Now that you have the Container App FQDN, go back to the app registration and add the redirect URIs:

```bash
CLIENT_ID=<your-app-id>
FQDN=<your-container-app-fqdn>

az ad app update --id $CLIENT_ID \
  --web-redirect-uris \
    "https://$FQDN/api/auth/callback/microsoft-entra-id" \
    "https://$FQDN/api/auth/onboard-callback"
```

## Updating to a New Version

```bash
az containerapp update -n $CA -g $RG \
  --image ghcr.io/holgerimbery/lab-tenant-manager:latest
```

To pin to a specific tag:

```bash
az containerapp update -n $CA -g $RG \
  --image ghcr.io/holgerimbery/lab-tenant-manager:v1.2.0
```
