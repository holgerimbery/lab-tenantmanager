# Changelog

## [Unreleased]

## [1.0.0] — Initial Release

### Features
- Multi-tenant onboarding via delegated consent flow
- Power Platform Developer environment provisioning (with Dataverse) per participant
- Workshop code system with optional expiry and usage limits
- Automated credential email delivery via operator-tenant `Mail.Send`
- Pre-flight checks (tenant reachability, licenses, delegated token)
- Lab cleanup — removes `labadmin*` users and their environments
- Re-authorization flow for expired delegated Power Platform tokens
- Per-tenant email sender override and welcome message
- Audit trail per tenant
- Managed identity for ACR pull and Key Vault access
- Deployed as Azure Container App from `ghcr.io/holgerimbery/lab-tenant-manager:latest`
