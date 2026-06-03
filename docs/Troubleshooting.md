# Troubleshooting

## `TypeError: Invalid URL` during onboarding callback

**Cause:** `KEY_VAULT_URI` environment variable is not set or is empty.

**Fix:**

```bash
az containerapp show -n ca-ltm -g rg-lab-tenant-manager \
  --query "properties.template.containers[0].env[?contains(name,'KEY_VAULT')]"
```

If missing, set it:

```bash
KV_URI=$(az keyvault show -n <your-kv-name> -g rg-lab-tenant-manager --query properties.vaultUri -o tsv)
az containerapp update -n ca-ltm -g rg-lab-tenant-manager \
  --set-env-vars "KEY_VAULT_URI=$KV_URI"
```

---

## Dataverse not provisioned in Developer environments

**Cause:** Delegated Power Platform token is missing or expired.

**Fix:**
1. Run **Pre-flight checks** on the tenant page — check #4 reports token status.
2. If missing, click **🔄 Re-authorize Delegated Token** and send the URL to the lab tenant Global Admin.
3. Re-run provisioning after the token is refreshed.

> Without the Power Platform delegated token, Developer environments are created without Dataverse.

---

## Credential email returns 403 or is not delivered

**Cause:** `Mail.Send` application permission not granted, wrong sender UPN, or sender mailbox not in the operator tenant.

**Fix:**

1. Verify `Mail.Send` is listed as an **Application** permission (not Delegated):
```bash
az ad app permission list --id $CLIENT_ID --query "[?resourceAppId=='00000003-0000-0000-c000-000000000000'].resourceAccess"
```

2. Confirm admin consent — each row must show a green ✅ in the portal:
```bash
az ad app permission admin-consent --id $CLIENT_ID
```

3. Verify the sender address in `MAIL_SENDER_UPN` is a mailbox that exists in the **operator tenant** (the tenant identified by `OPERATOR_TENANT_ID`).

4. Confirm `OPERATOR_TENANT_ID` is the tenant GUID of the **operator tenant**, not a lab tenant.

---

## Container scales to zero — provisioning jobs are lost

**Cause:** `minReplicas` is set to 0.

**Fix:**

```bash
az containerapp update -n ca-ltm -g rg-lab-tenant-manager --min-replicas 1
```

Verify:

```bash
az containerapp show -n ca-ltm -g rg-lab-tenant-manager \
  --query "properties.template.scale"
```

---

## Pre-flight check #4 fails — delegated token missing

See [Onboarding a Lab Tenant → Re-authorizing an Expired Delegated Token](Onboarding-a-Lab-Tenant.md#re-authorizing-an-expired-delegated-token).

---

## App returns 401 / AADSTS errors on sign-in

**Cause:** `OPERATOR_TENANT_ID` mismatch, or redirect URI not registered.

**Fix:**

1. Verify `OPERATOR_TENANT_ID` matches the tenant where the app registration was created:
```bash
az containerapp show -n ca-ltm -g rg-lab-tenant-manager \
  --query "properties.template.containers[0].env[?name=='OPERATOR_TENANT_ID'].value" -o tsv
```

2. Verify redirect URIs are registered on the app registration:
```bash
az ad app show --id $CLIENT_ID --query web.redirectUris
```

---

## Viewing Container App Logs

```bash
# Stream live logs
az containerapp logs show -n ca-ltm -g rg-lab-tenant-manager --follow

# Last 100 lines
az containerapp logs show -n ca-ltm -g rg-lab-tenant-manager --tail 100
```

---

## Checking the Current Image Version

```bash
az containerapp show -n ca-ltm -g rg-lab-tenant-manager \
  --query "properties.template.containers[0].image" -o tsv
```
