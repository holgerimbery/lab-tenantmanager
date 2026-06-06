# Lab Tenant Manager

> Automate Microsoft 365 lab-tenant provisioning for Power Platform workshops — deployed in minutes to your own Azure subscription.
[![Container image](https://img.shields.io/badge/image-ghcr.io%2Fholgerimbery%2Flab--tenant--manager-blue)](https://ghcr.io/holgerimbery/lab-tenant-manager)  
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fholgerimbery%2Flab-tenantmanager%2Fmain%2Fdeploy%2Fazuredeploy.json)  
> ⚠️ Before deploying, complete the required setup in [Prerequisites](#prerequisites) and [Step 1 — App Registration](#step-1--app-registration).


---

## What is Lab Tenant Manager?

**Lab Tenant Manager** is a SaaS web application that helps workshop operators manage Microsoft 365 **lab tenants** used in Power Platform trainings.  
It automates the full lifecycle: tenant onboarding, pre-flight checks, participant code generation, per-user Power Platform environment provisioning, and credential email delivery — all without giving participants direct admin access to the lab tenant.

The application runs as an **Azure Container App** in your own Azure subscription and is delivered as a pre-built container image — no build step required.

> **Container image:** `ghcr.io/holgerimbery/lab-tenant-manager:latest`

---

## Features

- **Multi-tenant onboarding** — add any Microsoft 365 tenant as a "lab tenant" via a one-time global-admin consent URL; no recurring access required
- **Power Platform environment provisioning** — creates one personal Developer environment (with Dataverse) per participant, routed to the Maker Welcome experience
- **Workshop code system** — generate shareable codes with optional expiry and usage limits; participants redeem them at a self-service portal
- **Automated credential emails** — sends username, password, Power Apps URL, and Copilot Studio URL from your operator-tenant mailbox; resend at any time
- **Pre-flight checks** — verify tenant licenses, delegated token availability, and security group membership before provisioning
- **Lab cleanup** — removes all `labadmin*` users and their environments to reset the tenant between workshops
- **Re-authorization flow** — refresh a lab tenant's delegated Power Platform token without repeating the full onboarding
- **Per-tenant email customization** — set a custom sender address and welcome message per lab tenant
- **Audit trail** — every provisioning and email action is logged per tenant
- **Zero standing credentials** — managed identity for Azure resource access; delegated tokens stored encrypted in Key Vault

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Operator Tenant (your tenant — hosts the SaaS admins)               │
│  ┌──────────────────────────┐   ┌───────────────────────────────┐    │
│  │  Azure Container App     │   │  Multi-tenant App Registration │    │
│  │  (Lab Tenant Manager)    │◄──│  • consented by each lab       │    │
│  └────────────┬─────────────┘   │    tenant at onboarding        │    │
│               │                 │  • OIDC login for SaaS admins  │    │
│  ┌────────────▼─────────────┐   │  • Mail.Send (Application)     │    │
│  │  Azure Cosmos DB         │   │    for credential emails       │    │
│  │  Azure Key Vault         │   └───────────────────────────────┘    │
│  └──────────────────────────┘  ← stores per-tenant refresh tokens    │
└──────────────────────────────────────────────────────────────────────┘
         │  MS Graph + Power Platform API (app + delegated)
         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Lab Tenant (demo Microsoft 365 tenant — one per client)             │
│  • Cleanup: removes labadmin* users + developer environments         │
│  • Per-user Power Platform Developer environments (with Dataverse)   │
│  • Security group → license assignment                               │
│  • Dataverse System Admin role for provisioned user + global admin   │
│  • Maker Welcome environment routing → user's own environment        │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

Before you deploy, you need:

- An **Azure subscription** with Contributor rights on a resource group
- A **Microsoft 365 operator tenant** (the tenant where your SaaS admins will sign in — this is *your* tenant, not the lab tenant)
- Azure CLI installed: `az version` ≥ 2.60 with `az bicep install`
- Your Entra ID **Object ID** for Key Vault admin access:

```bash
az ad signed-in-user show --query id -o tsv
```

---

## Step 1 — App Registration

Create a **multi-tenant** app registration in your **operator tenant**.

```bash
# Create the app registration
az ad app create \
  --display-name "Lab Tenant Manager" \
  --sign-in-audience AzureADMultipleOrgs
```

Note the `appId` (client ID) from the output.

### Redirect URIs

After the deployment in Step 2 completes, add these redirect URIs (replace `<fqdn>` with the Container App URL output):

```bash
CLIENT_ID=<your-app-id>
FQDN=<your-container-app-fqdn>

az ad app update --id $CLIENT_ID \
  --web-redirect-uris \
    "https://$FQDN/api/auth/callback/microsoft-entra-id" \
    "https://$FQDN/api/auth/onboard-callback"
```

### API Permissions — Application (no signed-in user required)

```bash
CLIENT_ID=<your-app-id>

# User.ReadWrite.All
az ad app permission add --id $CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 741f803b-c850-494e-b5df-cde7c675a1ca=Role

# Group.ReadWrite.All
az ad app permission add --id $CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 62a82d76-70ea-41e2-9197-370581804d09=Role

# Directory.ReadWrite.All
az ad app permission add --id $CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 19dbc75e-c2e2-444c-a770-ec69d8559fc7=Role

# LicenseAssignment.ReadWrite.All
az ad app permission add --id $CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 5facf0c1-8979-4e95-abcf-ff3d079771c0=Role

# Mail.Send
az ad app permission add --id $CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions b633e1c5-b582-4048-a93e-9f11b44c7e96=Role

# Grant admin consent for all Application permissions
az ad app permission admin-consent --id $CLIENT_ID
```

### API Permissions — Delegated (Power Platform, onboarding flow only)

The Power Platform service may not appear in the portal. Use the CLI:

```bash
# Power Platform — "User" scope (required to bootstrap Dataverse in Developer environments)
az ad app permission add --id $CLIENT_ID \
  --api 475226c6-020e-4fb2-8a90-7a972cbfc1d4 \
  --api-permissions 0eb56b90-a7b5-43b5-9402-8137a8083e90=Scope

az ad app permission grant --id $CLIENT_ID \
  --api 475226c6-020e-4fb2-8a90-7a972cbfc1d4 \
  --scope User
```

### Client Secret

```bash
az ad app credential reset --id $CLIENT_ID --append --display-name "lab-tenant-manager"
```

Note the `password` value — you will need it in Step 3.

---

## Step 2 — Deploy Azure Infrastructure

Click the button below or use the CLI commands. The deployment creates a Container App, Cosmos DB, Key Vault, and assigns all required managed-identity roles automatically.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fholgerimbery%2Flab-tenantmanager%2Fmain%2Fdeploy%2Fazuredeploy.json)
> ⚠️ Before deploying, complete the required setup in [Prerequisites](#prerequisites) and [Step 1 — App Registration](#step-1--app-registration).

### CLI alternative

```bash
RESOURCE_GROUP=rg-lab-tenant-manager
LOCATION=northeurope

az group create --name $RESOURCE_GROUP --location $LOCATION

az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-uri https://raw.githubusercontent.com/holgerimbery/lab-tenantmanager/main/deploy/azuredeploy.json \
  --parameters \
      baseName=ltm \
      kvAdminObjectId=<your-object-id>
```

**Resources created** (naming pattern uses your `baseName`):

| Resource | Name pattern |
|----------|-------------|
| Container App | `ca-<baseName>` |
| Container Apps Environment | `cae-<baseName>` |
| Cosmos DB account | `cosmos-<baseName>-…` |
| Key Vault | `kv-<baseName>-…` |
| Container Registry (ACR) | `acr<baseName>…` |

Note the `appUrl` output — this is your Container App FQDN.  
Go back to Step 1 and add the redirect URIs now.

---

## Step 3 — Configure the Container App

Replace all `<…>` placeholders with your actual values, then run:

```bash
CA=ca-ltm        # adjust if you used a different baseName
RG=rg-lab-tenant-manager

# Generate a random NextAuth secret
NEXTAUTH_SECRET=$(openssl rand -base64 32)
AUTH_SECRET=$(openssl rand -base64 32)

# Set secrets
az containerapp secret set -n $CA -g $RG --secrets \
  "ad-client-secret=<app-registration-client-secret>" \
  "nextauth-secret=$NEXTAUTH_SECRET" \
  "auth-secret=$AUTH_SECRET"

# Set environment variables (non-secret)
az containerapp update -n $CA -g $RG --set-env-vars \
  "AZURE_AD_CLIENT_ID=<app-registration-client-id>" \
  "OPERATOR_TENANT_ID=<your-operator-tenant-id>" \
  "NEXTAUTH_URL=https://<your-container-app-fqdn>" \
  "MAIL_SENDER_UPN=noreply@yourdomain.com" \
  "PP_DEFAULT_REGION=europe" \
  "PP_DEFAULT_CURRENCY=EUR" \
  "PP_DEFAULT_LANGUAGE=1033" \
  "USAGE_LOCATION=DE"

# Reference secrets in env vars
az containerapp update -n $CA -g $RG --set-env-vars \
  "AZURE_AD_CLIENT_SECRET=secretref:ad-client-secret" \
  "NEXTAUTH_SECRET=secretref:nextauth-secret" \
  "AUTH_SECRET=secretref:auth-secret"
```

### Environment variable reference

| Variable | Description | Example |
|----------|-------------|---------|
| `AZURE_AD_CLIENT_ID` | App registration client ID | `xxxxxxxx-…` |
| `AZURE_AD_CLIENT_SECRET` | App registration client secret | (secret ref) |
| `OPERATOR_TENANT_ID` | Your operator tenant GUID | `xxxxxxxx-…` |
| `NEXTAUTH_URL` | Full HTTPS URL of the Container App | `https://ca-ltm.…azurecontainerapps.io` |
| `NEXTAUTH_SECRET` | Random 32-byte base64 string | (secret ref) |
| `AUTH_SECRET` | Random 32-byte base64 string | (secret ref) |
| `MAIL_SENDER_UPN` | Mailbox in the operator tenant used as email sender | `noreply@yourdomain.com` |
| `PP_DEFAULT_REGION` | Power Platform region | `europe`, `unitedstates` |
| `PP_DEFAULT_CURRENCY` | Currency for new environments | `EUR`, `USD` |
| `PP_DEFAULT_LANGUAGE` | LCID for new environments | `1033` (English) |
| `USAGE_LOCATION` | ISO 3166-1 country for Entra ID user accounts | `DE`, `US` |

### Access model

New access model:

- **Master Admin** — sees and manages all tenants. Configured via `TENANT_MASTER_ADMIN_EMAILS`.
- **Tenant Admin** — can access and manage only the tenants they onboarded or were explicitly granted access to. Configured via `TENANT_ADMIN_EMAILS`.
- **Tenant ownership** — the user who onboards a tenant automatically becomes its manager.
- **Delegated management** — a tenant admin can share management rights with other admins directly from the tenant detail page.

Environment variables:

```bash
TENANT_ADMIN_EMAILS=user1@example.com,user2@example.com
TENANT_MASTER_ADMIN_EMAILS=masteradmin@example.com
```

If neither variable is set, the previous behavior is preserved for backward compatibility: all authenticated users are allowed.

---

## Step 4 — First Login & Onboarding

1. Navigate to `https://<your-container-app-fqdn>` and sign in with your **operator tenant** Microsoft account.
2. Go to **Tenants → New Tenant**, enter the lab tenant domain and an Entra ID security group name.
3. Copy the generated **onboarding URL** and open it as (or send it to) the lab tenant Global Admin — they grant consent once; the delegated Power Platform token is stored in Key Vault.
4. Run **Pre-flight checks** on the tenant page to verify licenses and token availability.
5. Go to the **Codes** tab, generate a workshop code, and share it with participants.

### Participant self-service

Participants go to `https://<your-fqdn>/redeem`, enter the workshop code and their email address, and receive their credentials on-screen and by email.

---

## Step 5 — Updating to a New Version

```bash
CA=ca-ltm
RG=rg-lab-tenant-manager

az containerapp update -n $CA -g $RG \
  --image ghcr.io/holgerimbery/lab-tenant-manager:latest
```

To pin to a specific release tag (e.g. `v1.2.0`):

```bash
az containerapp update -n $CA -g $RG \
  --image ghcr.io/holgerimbery/lab-tenant-manager:v1.2.0
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `TypeError: Invalid URL` during onboarding | `KEY_VAULT_URI` not set | Verify env var with `az containerapp show -n $CA -g $RG --query "properties.template.containers[0].env"` |
| Dataverse not created in Developer environments | Delegated Power Platform token missing | Run Pre-flight checks, then use **🔄 Re-authorize** on the tenant page |
| Credential email returns 403 | `Mail.Send` not granted or wrong sender UPN | Confirm Application permission + admin consent; sender must be a mailbox in the **operator tenant** |
| Container scales to zero, jobs lost | `minReplicas` set to 0 | `az containerapp update -n $CA -g $RG --min-replicas 1` |

For detailed diagnostics see the [Wiki](../../wiki).

---

## Copyright

Copyright (c) 2025 Holger Imbery. All rights reserved.
