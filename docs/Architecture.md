# Architecture

## Overview

Lab Tenant Manager is a multi-tenant SaaS web application running as an **Azure Container App** in your operator Azure subscription. It manages Microsoft 365 lab tenants for Power Platform workshops.

## System Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│  Operator Tenant (your Azure subscription)                           │
│                                                                      │
│  ┌──────────────────────────┐   ┌───────────────────────────────┐   │
│  │  Azure Container App     │   │  Multi-tenant App Registration │   │
│  │  lab-tenant-manager      │◄──│  • OIDC login (operator admins)│   │
│  │  (Next.js 14)            │   │  • Mail.Send (Application)     │   │
│  └────────────┬─────────────┘   │  • Graph + BAP app permissions │   │
│               │                 └───────────────────────────────┘   │
│  ┌────────────▼─────────────┐                                        │
│  │  Azure Cosmos DB         │  ← tenant, code, labuser, audit docs   │
│  │  Azure Key Vault         │  ← per-tenant delegated refresh tokens │
│  │  Azure Container Registry│  ← app image (private copy)           │
│  └──────────────────────────┘                                        │
└──────────────────────────────────────────────────────────────────────┘
         │
         │  MS Graph API (app permissions — client credentials)
         │  Power Platform BAP API (delegated — stored refresh token)
         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Lab Tenant (one per client — standard Microsoft 365 tenant)         │
│  • Create/delete labadmin* users                                     │
│  • Assign licenses via security group                                │
│  • Provision Power Platform Developer environments (with Dataverse)  │
│  • Set Maker Welcome routing per user                                │
└──────────────────────────────────────────────────────────────────────┘
```

## Azure Resources

| Resource | Purpose |
|----------|---------|
| **Azure Container App** | Hosts the web application (`minReplicas: 1` — background jobs run in-process) |
| **Container Apps Environment** | Networking boundary for the Container App |
| **Azure Cosmos DB** (serverless) | Stores tenant records, workshop codes, lab users, audit log, onboarding sessions |
| **Azure Key Vault** | Stores per-lab-tenant delegated refresh tokens, encrypted at rest by Azure |
| **Azure Container Registry** | Private copy of the container image (used for deployment) |

## Key Design Decisions

| Decision | Reason |
|----------|--------|
| Delegated token stored in Key Vault at onboarding | Dataverse bootstrap in Developer environments requires a licensed-user delegated token — app-only is insufficient |
| `minReplicas: 1` | Background provisioning jobs run in-process; scaling to zero would lose queued work |
| Single multi-tenant app registration | One registration works across all lab tenants; each lab admin consents once |
| Refresh token per tenant | Allows re-provisioning without requiring the global admin to consent again |
| Operator-tenant mailbox for email | `*.onmicrosoft.com` senders are often blocked externally; operator-tenant mailboxes are trusted |

## Data Model (Cosmos DB)

Container: `lab-data`, partition key: `/tenantId`

| `_type` | Description |
|---------|-------------|
| `tenant` | Lab tenant record — domain, group ID, status, global admin UPN, optional sender/welcome message |
| `code` | Workshop redemption codes with optional expiry and usage limit |
| `labuser` | Provisioned user — environment info, XOR-encrypted initial password, participant email |
| `audit` | Audit log entries per tenant (provisioned, email_resent, cleanup, etc.) |
| `onboarding_session` | Short-lived OAuth state (TTL 1 h); deleted after callback |

## Security Model

- SaaS admin access restricted to operator tenant via `OPERATOR_TENANT_ID`
- Lab tenant global admin credentials **never stored** — only a Key Vault-backed refresh token
- Managed identity used for ACR pull and Key Vault access (no stored credentials)
- Initial user passwords XOR-encrypted with `AUTH_SECRET` at rest
- All Graph operations on lab tenants use app-only client credentials after onboarding
