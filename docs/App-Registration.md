# App Registration

Create a **multi-tenant** app registration in your **operator tenant** (the tenant where your SaaS admins will sign in).

## 1. Create the Application

```bash
az ad app create \
  --display-name "Lab Tenant Manager" \
  --sign-in-audience AzureADMultipleOrgs
```

Note the `appId` (client ID) from the output.

## 2. Add Redirect URIs

After the Container App is deployed (Step 2 of the main guide), add redirect URIs.  
Replace `<fqdn>` with the Container App URL from the deployment output.

```bash
CLIENT_ID=<your-app-id>
FQDN=<your-container-app-fqdn>

az ad app update --id $CLIENT_ID \
  --web-redirect-uris \
    "https://$FQDN/api/auth/callback/microsoft-entra-id" \
    "https://$FQDN/api/auth/onboard-callback"
```

## 3. Application Permissions (no signed-in user)

These are required for all tenant management operations.

```bash
CLIENT_ID=<your-app-id>

# User.ReadWrite.All — create and delete lab users
az ad app permission add --id $CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 741f803b-c850-494e-b5df-cde7c675a1ca=Role

# Group.ReadWrite.All — manage security groups
az ad app permission add --id $CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 62a82d76-70ea-41e2-9197-370581804d09=Role

# Directory.ReadWrite.All — read tenant directory
az ad app permission add --id $CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 19dbc75e-c2e2-444c-a770-ec69d8559fc7=Role

# LicenseAssignment.ReadWrite.All — assign Microsoft 365 licenses
az ad app permission add --id $CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 5facf0c1-8979-4e95-abcf-ff3d079771c0=Role

# Mail.Send — send credential emails from operator-tenant mailbox
az ad app permission add --id $CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions b633e1c5-b582-4048-a93e-9f11b44c7e96=Role

# Grant admin consent in the operator tenant
az ad app permission admin-consent --id $CLIENT_ID
```

> All permissions should show a green ✅ in the Azure portal after admin consent is granted.

## 4. Power Platform Delegated Permission (onboarding only)

The Power Platform service (`475226c6-...`) does not appear in the portal "Add a permission" wizard by name. Use the CLI:

```bash
# Power Platform — "User" scope
# Required to bootstrap Dataverse in Developer environments during onboarding
az ad app permission add --id $CLIENT_ID \
  --api 475226c6-020e-4fb2-8a90-7a972cbfc1d4 \
  --api-permissions 0eb56b90-a7b5-43b5-9402-8137a8083e90=Scope

az ad app permission grant --id $CLIENT_ID \
  --api 475226c6-020e-4fb2-8a90-7a972cbfc1d4 \
  --scope User
```

This permission is requested in the onboarding consent flow (`prompt=consent`). The resulting refresh token is stored in Key Vault and reused for all subsequent Power Platform provisioning.

## 5. Create a Client Secret

```bash
az ad app credential reset \
  --id $CLIENT_ID \
  --append \
  --display-name "lab-tenant-manager"
```

Note the `password` value — you will use it as `AZURE_AD_CLIENT_SECRET` during deployment configuration.

> Secrets expire. When rotating, add the new secret first, update the Container App secret, then delete the old one.
