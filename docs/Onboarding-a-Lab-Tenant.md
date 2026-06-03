# Onboarding a Lab Tenant

## Overview

"Onboarding" means giving Lab Tenant Manager permission to manage a Microsoft 365 lab tenant. It requires the lab tenant's **Global Admin** to consent once via a URL you generate.

After onboarding, the app uses app-only client credentials (MS Graph) and a stored delegated Power Platform token (Key Vault) for all subsequent operations — no recurring access from the global admin.

---

## Operator Steps

### 1. Add the Tenant

1. Sign in to the app with your operator tenant account.
2. Go to **Tenants → New Tenant**.
3. Fill in:
   - **Domain** — the lab tenant's `*.onmicrosoft.com` domain (or primary custom domain)
   - **Security group name** — an Entra ID security group in the lab tenant that participants will be added to (the group must already exist)
4. Click **Save**. The tenant status will be `pending_consent`.

### 2. Generate the Onboarding URL

On the tenant detail page, click **Generate Onboarding Link**.  
Copy the URL — it encodes an OAuth state token and has a 30-minute expiry.

### 3. Send the URL to the Lab Tenant Global Admin

The lab tenant's Global Admin must open the URL in a browser where they are signed into the lab tenant. They will see a Microsoft consent screen requesting:

- All Application permissions (Graph — User, Group, Directory, License, Mail.Send)
- Power Platform delegated permission (`User` scope)

Once they consent, the app stores the delegated refresh token in Key Vault and marks the tenant as `active`.

---

## Pre-flight Checks

Before running a workshop, use **Pre-flight checks** on the tenant detail page to verify:

| Check | Description |
|-------|-------------|
| ✅ Tenant reachable | App can authenticate to the lab tenant via client credentials |
| ✅ Security group exists | The configured group ID resolves in the tenant directory |
| ✅ Licenses available | Sufficient Microsoft 365 licenses for the expected participant count |
| ✅ Delegated token valid | Power Platform refresh token is present in Key Vault and can be exchanged |

If check #4 fails, use **🔄 Re-authorize Delegated Token** (see below).

---

## Running a Workshop

1. Go to the **Codes** tab on the tenant page.
2. Click **New Code** — set an optional expiry date and usage limit.
3. Optionally set a **Sender Email Address** override (must be a mailbox in your operator tenant).
4. Optionally add a **Welcome Message** included at the top of each credential email.
5. Share the code with participants — they go to `https://<your-fqdn>/redeem`.

### Participant flow

1. Participant opens `/redeem`, enters the workshop code and their personal email address.
2. The app creates a `labadmin*` user in the lab tenant, assigns a license via the security group, provisions a Power Platform Developer environment, sets Dataverse System Admin role, and routes the Maker Welcome experience to the personal environment.
3. Credentials (username, password, Power Apps URL, Copilot Studio URL) are shown on screen and sent by email.

---

## Re-authorizing an Expired Delegated Token

Power Platform delegated refresh tokens can expire (typically after 90 days of inactivity) or may be missing if the global admin skipped Power Platform consent during onboarding.

1. On the tenant detail page, click **🔄 Re-authorize Delegated Token**.
2. A new consent URL is generated. Send it to the lab tenant Global Admin.
3. After they consent, the token in Key Vault is refreshed — no other tenant data is affected.

---

## Resetting a Tenant Between Workshops

The **Cleanup** action on the tenant page removes all `labadmin*` users and their Developer environments, ready for the next workshop.

```bash
# You can also verify cleanup via CLI:
az containerapp logs show -n ca-ltm -g rg-lab-tenant-manager --follow
```

---

## Managing Claimed Users

On the **Users** tab of a tenant:

- See all provisioned accounts with claim status and participant email
- Edit the participant email address inline
- Click ✉️ to resend the credential email at any time
