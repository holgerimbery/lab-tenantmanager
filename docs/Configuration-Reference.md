# Configuration Reference

All environment variables for the Container App.

## Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `AZURE_AD_CLIENT_ID` | App registration client ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_AD_CLIENT_SECRET` | App registration client secret (use `secretref:`) | *(secret ref)* |
| `OPERATOR_TENANT_ID` | Tenant GUID of the operator tenant (where admins sign in) | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `NEXTAUTH_URL` | Full HTTPS URL of the Container App | `https://ca-ltm.livelyplant-….azurecontainerapps.io` |
| `NEXTAUTH_SECRET` | Random 32-byte base64 string (use `secretref:`) | *(secret ref)* |
| `AUTH_SECRET` | Random 32-byte base64 string — also used to XOR-encrypt stored passwords (use `secretref:`) | *(secret ref)* |
| `MAIL_SENDER_UPN` | UPN of the mailbox in the **operator tenant** used as email sender | `noreply@yourdomain.com` |

## Power Platform Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `PP_DEFAULT_REGION` | Power Platform region for new environments | `unitedstates` | `europe`, `unitedstates`, `asia` |
| `PP_DEFAULT_CURRENCY` | Currency code for new environments | `USD` | `EUR`, `USD`, `GBP` |
| `PP_DEFAULT_LANGUAGE` | LCID integer for new environments | `1033` | `1033` (English), `1031` (German) |
| `USAGE_LOCATION` | ISO 3166-1 alpha-2 country for Entra ID user `usageLocation` | `DE` | `DE`, `US`, `GB` — required for license assignment |

## Auto-wired Variables (set by Bicep)

These are set automatically during deployment and should not be changed manually:

| Variable | Source |
|----------|--------|
| `NODE_ENV` | Bicep (`production`) |
| `PORT` | Bicep (`3000`) |
| `COSMOS_ENDPOINT` | Bicep output — Cosmos DB endpoint |
| `COSMOS_DATABASE` | Bicep output — database name |
| `COSMOS_CONTAINER` | Bicep output — container name |
| `KEY_VAULT_URI` | Bicep output — Key Vault URI |

> The app accepts both `KEY_VAULT_URI` and `KEY_VAULT_URL`. If you see `TypeError: Invalid URL` during onboarding, verify this variable is set.

## Generating Secrets

```bash
# Generate random secrets on Linux/macOS
openssl rand -base64 32   # NEXTAUTH_SECRET
openssl rand -base64 32   # AUTH_SECRET

# On Windows (PowerShell)
[Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 }))
```

## Rotating the Client Secret

```bash
CA=ca-ltm
RG=rg-lab-tenant-manager

# 1. Create a new secret in the app registration
az ad app credential reset --id $CLIENT_ID --append --display-name "lab-tenant-manager-v2"
# Note the new password

# 2. Update the Container App secret
az containerapp secret set -n $CA -g $RG --secrets \
  "ad-client-secret=<new-secret>"

# 3. Restart to pick up the new secret value
az containerapp revision restart -n $CA -g $RG \
  --revision $(az containerapp show -n $CA -g $RG \
    --query "properties.latestRevisionName" -o tsv)

# 4. Delete the old secret from the app registration
az ad app credential list --id $CLIENT_ID   # find the old key ID
az ad app credential delete --id $CLIENT_ID --key-id <old-key-id>
```
