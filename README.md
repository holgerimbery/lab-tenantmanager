# MATE365 — Tenant Manager

> Automate your workshops, labs, and development environments — for Power Platform, Copilot Studio & AI. Deployed in minutes to your own Azure subscription.

[![Container image](https://img.shields.io/badge/image-ghcr.io%2Fholgerimbery%2Flab--tenant--manager-blue)](https://ghcr.io/holgerimbery/lab-tenant-manager)  
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fholgerimbery%2Flab-tenantmanager%2Fmain%2Fdeploy%2Fazuredeploy.json)  
> ⚠️ Before deploying, complete the required setup in [Prerequisites](#prerequisites) and [Step 1 — App Registration](#step-1--app-registration).


[website with gallery](https://holgerimbery.github.io/lab-tenantmanager/)


---

## What is MATE365?

**MATE365 — Tenant Manager** is a SaaS web application for managing Microsoft 365 tenants for **workshops and labs** and **ongoing development** with Power Platform, Copilot Studio & AI. It provides two equally supported modes:

- **Workshop and lab management** — automate tenant onboarding, pre-flight checks, participant code generation, per-user Power Platform environment provisioning, and credential email delivery, without giving participants direct admin access to the tenant.
- **Development environment management** — members of an existing Entra security group sign in with their own accounts and create, renew, and delete Power Platform developer environments themselves, with required licenses, quotas, DLP policies, and retention enforced.

The application runs as an **Azure Container App** in your own Azure subscription and is delivered as a pre-built container image — no build step required.

> **Container image:** `ghcr.io/holgerimbery/lab-tenant-manager:latest`

### Two modes

Choose the mode per tenant when you onboard it. Both modes can run side by side in one installation, using separate tenants, and a **Mode** column shows each tenant's mode.

| | 🎓 **Workshop lab** | 🛠️ **Development environment manager** |
|---|---|---|
| **For** | Trainings, hackathons, demos | Teams who build on Power Platform |
| **Who** | Participants with a workshop code | Members of an existing Entra security group |
| **Accounts** | App creates `labadmin*` accounts (or uses group members) | Members use their **own** work accounts |
| **Environments** | One Developer environment per account, pre-provisioned by the app | Members create, renew and delete their own in a **maker portal** |
| **Governance** | Licenses via security group, cleanup after the workshop | Required licenses, quotas, region, DLP policies, retention, optional Managed Environment groups |
| **Entry point** | `https://<fqdn>/redeem` | `https://<fqdn>/sign-in?portal=developer` |

---

## Features

- **Multi-tenant onboarding** — add any Microsoft 365 tenant via a one-time global-admin consent URL; choose *Workshop lab* or *Development environments* and the app opens the right setup page
- **Security-group participants** — use members of an existing Entra security group instead of created accounts; required licenses and free seats are checked against the member count
- **Development environment manager** — group members create, renew and delete their own developer environments in a maker portal; quotas, region, DLP, retention and optional environment groups are enforced
- **Workshop and development side by side** — a Mode column shows each tenant's mode
- **Power Platform environment provisioning** — creates one personal Developer environment (with Dataverse) per participant, routed to the Maker Welcome experience
- **Workshop code system** — generate shareable codes with optional expiry and usage limits; participants redeem them at a self-service portal
- **Automated credential emails** — sends username, password, Power Apps URL, and Copilot Studio URL from your operator-tenant mailbox; resend at any time
- **Workshop sessions and participant support** — organize workshop sessions with time-limited instructor access, participant workspaces, and a session-scoped help board
- **Developer portal readiness and recovery** — guided configuration readiness, read-only eligibility previews, admin diagnostics, per-user license repair, and safe environment recovery
- **Operational readiness and cleanup** — readiness snapshots, cleanup previews, an audit and recovery timeline, and holds for operational follow-up
- **Starter kits and solution management** — reusable starter kits, a private global GitHub catalog, exact-commit imports, recoverable review-PR exports, and stored solution ZIP deletion
- **Lifecycle notifications** — an in-app inbox and opt-in email notifications; lifecycle email uses the operator mailbox when configured
- **Reliable administration** — permission and consent checks, delegated-email diagnostics, and recovery from transient Graph throttling
- **Pre-flight checks** — verify tenant licenses, delegated token availability, and security group membership before provisioning
- **Lab cleanup** — removes only the accounts and environments the app created, to reset the tenant between workshops
- **Safe recovery** — retry a failed participant environment or Lab - Admin / Lab - Target without rerunning setup or creating duplicates
- **Re-authorization flow** — refresh a lab tenant's delegated Power Platform token without repeating the full onboarding
- **Per-tenant email customization** — set a custom sender address and welcome message per lab tenant
- **Audit trail** — every provisioning and email action is logged per tenant
- **Managed identity for Azure access** — the Container App's managed identity pulls from ACR and reads Key Vault. Cosmos DB uses its account key and the app registration uses a client secret; both are stored as Container App secrets, not in plain environment variables. Delegated Power Platform tokens are stored encrypted in Key Vault

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Operator Tenant (your tenant — hosts the SaaS admins)               │
│  ┌──────────────────────────┐   ┌───────────────────────────────┐    │
│  │  Azure Container App     │   │  Multi-tenant App Registration │    │
│  │  (MATE365)               │◄──│  • consented by each managed   │    │
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
│  Managed Tenant (Microsoft 365 — workshop/lab or development)        │
│  • Workshop: labadmin* accounts, each with its own Developer env     │
│  • Development: group members create governed Developer envs         │
│    themselves in the maker portal (licenses, quotas, DLP)            │
│  • Cleanup: removes only what the app created                        │
│  • Per-user Power Platform Developer environments (with Dataverse)   │
│  • Security group → license assignment                               │
│  • Dataverse System Admin role for provisioned user + global admin   │
│  • Maker Welcome environment routing → user's own environment        │
└──────────────────────────────────────────────────────────────────────┘
```

--- 

## Documentation

[Full Documentation](https://github.com/holgerimbery/lab-tenantmanager/wiki)  
Quickstart - [below](https://github.com/holgerimbery/lab-tenantmanager/blob/main/README.md#prerequisites)

---

## Prerequisites

Before you deploy, you need:

- An **Azure subscription** with Contributor rights on a resource group
- A **Microsoft 365 operator tenant** (the tenant where your SaaS admins will sign in — this is *your* tenant, not the tenant managed for workshops, labs, or development)
- Azure CLI installed: `az version` ≥ 2.60
- Your Entra ID **Object ID** for Key Vault admin access:

```bash
az ad signed-in-user show --query id -o tsv
```

### Additional prerequisites for development-environment tenants

Only needed if you onboard a tenant in **🛠️ Development environments** mode:

- An **existing Entra security group** in that tenant — its members create the environments
- The required **licenses** for the group members (for example the Power Apps Developer Plan)
- At least one existing **tenant DLP policy** — note its GUID
- The **`tenant-maker` redirect URI** (`https://<fqdn>/api/auth/callback/tenant-maker`, see [Step 1](#redirect-uris))
- **`DEVELOPMENT_WORKER_ENABLED=true`** and at least one replica (`minReplicas: 1`) so the worker processes jobs. New ARM deployments set both; deployments created before v0.7.0 need `az containerapp update -n <ca> -g <rg> --set-env-vars DEVELOPMENT_WORKER_ENABLED=true`

See [Development Environments](https://github.com/holgerimbery/lab-tenantmanager/wiki/Development-Environments) for the full setup.

---

## Step 1 — App Registration

> 💡 **Quick path (recommended):** Run the automated bootstrap script. It verifies required CLI tools and modules, logs into your tenant, lets you choose your subscription, creates the multi-tenant app registration, assigns all permissions, grants admin consent, and generates the client secret in one step without manual GUID copying.
>
> **PowerShell:**
> ```powershell
> .\deploy\scripts\setup-prerequisites.ps1
> ```
>
> **Bash:**
> ```bash
> ./deploy/scripts/setup-prerequisites.sh
> ```
>
> *Security notice: The bootstrap script prints secrets to the console only. Never commit secrets to git.*

If you prefer to configure the app registration manually, follow the steps below.

> ℹ️ *Note: The permission GUIDs in the commands below are fixed Microsoft identifiers — copy them as-is. Only `CLIENT_ID` and `FQDN` are your custom values.*

Create a **multi-tenant** app registration in your **operator tenant**.

```bash
# Create the app registration
az ad app create \
  --display-name "MATE365 — Tenant Manager" \
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
    "https://$FQDN/api/auth/onboard-callback" \
    "https://$FQDN/api/auth/adminconsent-callback" \
    "https://$FQDN/api/auth/callback/tenant-maker"
```

`tenant-maker` is the maker portal sign-in used by development tenants.

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

Select the required **powerPlatformGeography** once. The template automatically sets both
`PP_DEFAULT_REGION` and `PP_PAC_MACRO_REGION`; no post-deployment PAC configuration is needed.
This choice is separate from the Azure hosting `location`.

| Geography | PAC residency boundary | Legacy BAP default |
|----------|------------------------|--------------------|
| `north-america` | United States or Canada | `unitedstates` |
| `the-americas` | North or South America | `unitedstates` |
| `eu-efta` | EU/EFTA (EU Data Boundary) | `europe` |
| `europe-uk` | EU/EFTA or UK; not UK-only or EUDB | `europe` |
| `emea` | Europe, UK, Middle East or Africa | `europe` |
| `asia-pacific` | Asia-Pacific | `australia` |

The BAP default is a legacy location within the chosen boundary, not a prediction of PAC's
capacity-based placement. Australia avoids legacy `asia`, which can include Hong Kong outside
the macro-region's current placement set. See [Microsoft's macro-region guidance](https://learn.microsoft.com/power-platform/admin/macro-regions).
The PAC boundary applies across tenants in this deployment; use separate deployments for different
required boundaries. Existing environments are not moved.

To check the template's required geography and environment wiring offline, run
`node --test deploy/azuredeploy.test.cjs` (Node.js 20+; no dependencies or Azure resources required).

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
      kvAdminObjectId=<your-object-id> \
      powerPlatformGeography=eu-efta
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

Step 2 initially runs Microsoft's public hello-world image on port 80. It does not
authenticate to ACR during bootstrap; the app's managed identity receives `AcrPull`
after the app exists. This placeholder is **not** the application — it has no secrets
and no database access. Configuration turns it into the running app: it stores the
secrets, sets the environment variables, switches ingress to port 3000, and replaces
the placeholder with the MATE365 image.

### Easy path — configuration script

The PowerShell script discovers the Container App, Cosmos account and FQDN from the
deployment outputs, retrieves the Cosmos key, sets every secret and environment variable
(including the `COSMOS_KEY` secret reference and the master-admin allow-list), switches to
port 3000 and the GHCR image, and adds the four redirect URIs. It checks each Azure CLI
exit code and never prints or stores secrets.

```powershell
./deploy/scripts/configure-containerapp.ps1 `
  -ResourceGroup rg-lab-tenant-manager `
  -ClientId <app-registration-client-id> `
  -OperatorTenantId <your-operator-tenant-id> `
  -MasterAdminEmails admin@yourdomain.com `
  -MailSenderUpn noreply@yourdomain.com
```

You are prompted securely for the client secret (no echo). Skip ahead to
[Step 4](#step-4--first-login--onboarding) once it completes.

### Manual path — Azure CLI

Replace all `<…>` placeholders with your actual values, then run:

```bash
CA=ca-ltm          # adjust if you used a different baseName
RG=rg-lab-tenant-manager
COSMOS=cosmos-ltm  # from deployment output: cosmosAccountName

# Cosmos primary key — the app authenticates to Cosmos DB with this account key.
# Without it, every request fails with "Required Header authorization is missing".
COSMOS_KEY=$(az cosmosdb keys list -n $COSMOS -g $RG --type keys \
  --query primaryMasterKey -o tsv)

# Generate random NextAuth/Auth secrets
NEXTAUTH_SECRET=$(openssl rand -base64 32)
AUTH_SECRET=$(openssl rand -base64 32)

# Set secrets
az containerapp secret set -n $CA -g $RG --secrets \
  "cosmos-key=$COSMOS_KEY" \
  "ad-client-secret=<app-registration-client-secret>" \
  "nextauth-secret=$NEXTAUTH_SECRET" \
  "auth-secret=$AUTH_SECRET"

# Set environment variables (non-secret). Set the master-admin allow-list so /admin is reachable.
az containerapp update -n $CA -g $RG --set-env-vars \
  "AZURE_AD_CLIENT_ID=<app-registration-client-id>" \
  "OPERATOR_TENANT_ID=<your-operator-tenant-id>" \
  "NEXTAUTH_URL=https://<your-container-app-fqdn>" \
  "MAIL_SENDER_UPN=noreply@yourdomain.com" \
  "TENANT_MASTER_ADMIN_EMAILS=admin@yourdomain.com" \
  "PP_DEFAULT_CURRENCY=EUR" \
  "PP_DEFAULT_LANGUAGE=1033" \
  "USAGE_LOCATION=DE"

# Reference secrets in env vars (COSMOS_KEY included)
az containerapp update -n $CA -g $RG --set-env-vars \
  "COSMOS_KEY=secretref:cosmos-key" \
  "AZURE_AD_CLIENT_SECRET=secretref:ad-client-secret" \
  "NEXTAUTH_SECRET=secretref:nextauth-secret" \
  "AUTH_SECRET=secretref:auth-secret"

# Replace the bootstrap image and switch ingress to the application's port
az containerapp ingress update -n $CA -g $RG --target-port 3000
az containerapp update -n $CA -g $RG \
  --image ghcr.io/holgerimbery/lab-tenant-manager:latest
```

A healthy revision or an allocated FQDN does **not** prove database access. After the new
revision is ready, sign in at `https://<your-fqdn>/sign-in` and open `https://<your-fqdn>/admin`
to confirm Cosmos connectivity.

### Environment variable reference

| Variable | Description | Example |
|----------|-------------|---------|
| `AZURE_AD_CLIENT_ID` | App registration client ID | `xxxxxxxx-…` |
| `AZURE_AD_CLIENT_SECRET` | App registration client secret | (secret ref) |
| `COSMOS_KEY` | Cosmos DB primary key used to authenticate to Cosmos (required) | (secret ref) |
| `OPERATOR_TENANT_ID` | Your operator tenant GUID | `xxxxxxxx-…` |
| `NEXTAUTH_URL` | Full HTTPS URL of the Container App | `https://ca-ltm.…azurecontainerapps.io` |
| `NEXTAUTH_SECRET` | Random 32-byte base64 string | (secret ref) |
| `AUTH_SECRET` | Random 32-byte base64 string | (secret ref) |
| `MAIL_SENDER_UPN` | Mailbox in the operator tenant used as email sender | `noreply@yourdomain.com` |
| `PP_DEFAULT_REGION` | Legacy BAP location derived by the template from `powerPlatformGeography`; do not override during initial setup | `europe`, `unitedstates`, `australia` |
| `PP_DEFAULT_CURRENCY` | Currency for new environments | `EUR`, `USD` |
| `PP_DEFAULT_LANGUAGE` | LCID for new environments | `1033` (English) |
| `USAGE_LOCATION` | ISO 3166-1 country for Entra ID user accounts | `DE`, `US` |
| `DEVELOPMENT_WORKER_ENABLED` | Runs the development-environment worker (set by the template) | `true` |
| `PP_PAC_MACRO_REGION` | PAC macro-region set automatically by the template from `powerPlatformGeography` | `eu-efta`, `europe-uk` |

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

1. Navigate to `https://<your-container-app-fqdn>/sign-in` and sign in with your **operator tenant** Microsoft account. The Admin Portal dashboard is at `https://<your-container-app-fqdn>/admin`; the root URL redirects participants to `/redeem`.
2. Go to **Tenants → Onboard Tenant**, choose **🎓 Workshop lab** or **🛠️ Development environments**, and enter the tenant domain.
3. Copy the generated **onboarding URL** and open it as (or send it to) the tenant's Global Admin — they grant consent once. The app then opens the right next step automatically.
4. **Workshop lab:** complete the setup wizard, run **Pre-flight checks**, then open **Manage Codes**, generate a workshop code and share it with participants.
5. **Development environments:** follow the *Getting started* checklist on **Participants & development** — pick the security group, required licenses and policy (region, quotas, DLP), save, review the read-only eligibility preview, then share the maker portal link. Admin diagnostics and per-user license repair are available when follow-up is needed.

### Participant self-service

- **Workshop:** participants go to `https://<your-fqdn>/redeem`, enter the workshop code and their email address, and receive their credentials on-screen and by email. Workshop sessions can also provide participant workspaces and a session-scoped help board.
- **Development:** members open `https://<your-fqdn>/sign-in?portal=developer`, sign in with their own account, and create, renew or delete their developer environments.

---

## Step 5 — Updating to a New Version

```bash
CA=ca-ltm
RG=rg-lab-tenant-manager

az containerapp update -n $CA -g $RG \
  --image ghcr.io/holgerimbery/lab-tenant-manager:latest
```

To pin to a specific release tag (e.g. `v0.7.0`):

```bash
az containerapp update -n $CA -g $RG \
  --image ghcr.io/holgerimbery/lab-tenant-manager:v0.7.0
```

### Upgrading to 0.7.0

Image updates keep your environment variables. Existing deployments additionally need:

1. The redirect URIs `/api/auth/adminconsent-callback` and `/api/auth/callback/tenant-maker` (see [Redirect URIs](#redirect-uris) — the command replaces the whole list, so pass all four).
2. The development worker: `az containerapp update -n $CA -g $RG --set-env-vars DEVELOPMENT_WORKER_ENABLED=true`

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `TypeError: Invalid URL` during onboarding | `KEY_VAULT_URI` not set | Verify env var with `az containerapp show -n $CA -g $RG --query "properties.template.containers[0].env"` |
| Dataverse not created in Developer environments | Delegated Power Platform token missing | Run Pre-flight checks, then use **🔄 Re-authorize** on the tenant page |
| Credential email returns 403 | `Mail.Send` not granted or wrong sender UPN | Confirm Application permission + admin consent; sender must be a mailbox in the **operator tenant** |
| Container scales to zero, jobs lost | `minReplicas` set to 0 | `az containerapp update -n $CA -g $RG --min-replicas 1` |
| A participant environment failed | Transient Power Platform error | **Lab Users → Retry environment** (no duplicates); for Lab - Admin / Target use the retry button on the tenant page |
| Maker portal sign-in fails | `tenant-maker` redirect URI missing | Add all four redirect URIs from Step 1 |
| Development environments stay queued | Worker not running | Set `DEVELOPMENT_WORKER_ENABLED=true`, keep `minReplicas` 1 |
| Developer environment fails outside the US | Older deployment lacks PAC macro-region configuration | Check `powerPlatformGeography` and its two template-wired region variables; image-only updates retain old settings |
| Removing a tenant returns 409 | Development environments still exist | Delete them on **Participants & development** first |

For detailed diagnostics see the [Wiki](https://github.com/holgerimbery/lab-tenantmanager/wiki).

---

## Copyright

Copyright (c) 2025 Holger Imbery. All rights reserved.
