<#
.SYNOPSIS
    Completes Step 3 — configures the deployed Lab Tenant Manager Container App.

.DESCRIPTION
    Runs the full post-deployment configuration in one reliable pass:
      * discovers the Container App, Cosmos account and FQDN from the ARM deployment outputs,
      * retrieves the Cosmos primary key and stores it as the 'cosmos-key' Container App secret,
      * sets the application secrets (Cosmos key, client secret, NextAuth/Auth secrets),
      * sets the non-secret environment variables including the master-admin allow-list,
      * wires every secret into its environment variable via secretref (COSMOS_KEY included),
      * switches ingress to port 3000 and replaces the bootstrap placeholder with the GHCR image,
      * adds the four app-registration redirect URIs for the discovered FQDN.

    The initial deployment runs a public hello-world placeholder on port 80. This script turns
    that placeholder into the configured application. Secrets and keys are never printed to the
    console and are never written to disk.

.PARAMETER ResourceGroup
    Resource group that contains the deployment. Required.

.PARAMETER ClientId
    App registration (client) ID from Step 1. Required.

.PARAMETER OperatorTenantId
    Operator tenant GUID (where admins sign in). Required.

.PARAMETER MasterAdminEmails
    Comma-separated allow-list for TENANT_MASTER_ADMIN_EMAILS. Required so /admin is reachable;
    without it every authenticated user is treated as an admin.

.PARAMETER MailSenderUpn
    Mailbox UPN in the operator tenant used as the credential-email sender. Required.

.PARAMETER ClientSecret
    App registration client secret. If omitted, the script prompts for it securely (no echo).

.PARAMETER DeploymentName
    ARM deployment name to read outputs from. Default: 'azuredeploy'.

.PARAMETER ContainerAppName
    Container App name. Optional; discovered from the deployment outputs when omitted.

.PARAMETER CosmosAccountName
    Cosmos DB account name. Optional; discovered from the deployment outputs when omitted.

.PARAMETER Fqdn
    Container App FQDN. Optional; discovered from the deployment outputs when omitted.

.PARAMETER Image
    Application image to switch to. Default: 'ghcr.io/holgerimbery/lab-tenant-manager:latest'.

.PARAMETER DefaultCurrency
    PP_DEFAULT_CURRENCY value. Default: 'EUR'.

.PARAMETER DefaultLanguage
    PP_DEFAULT_LANGUAGE LCID. Default: '1033'.

.PARAMETER UsageLocation
    USAGE_LOCATION ISO 3166-1 alpha-2 country. Default: 'DE'.

.PARAMETER SkipRedirectUris
    Skip updating the app-registration redirect URIs (for example when they already exist).

.EXAMPLE
    ./configure-containerapp.ps1 -ResourceGroup rg-lab-tenant-manager `
      -ClientId <app-id> -OperatorTenantId <tenant-id> `
      -MasterAdminEmails admin@contoso.com -MailSenderUpn noreply@contoso.com
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$OperatorTenantId,

    [Parameter(Mandatory = $true)]
    [string]$MasterAdminEmails,

    [Parameter(Mandatory = $true)]
    [string]$MailSenderUpn,

    [Parameter(Mandatory = $false)]
    [securestring]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [string]$DeploymentName = "azuredeploy",

    [Parameter(Mandatory = $false)]
    [string]$ContainerAppName,

    [Parameter(Mandatory = $false)]
    [string]$CosmosAccountName,

    [Parameter(Mandatory = $false)]
    [string]$Fqdn,

    [Parameter(Mandatory = $false)]
    [string]$Image = "ghcr.io/holgerimbery/lab-tenant-manager:latest",

    [Parameter(Mandatory = $false)]
    [string]$DefaultCurrency = "EUR",

    [Parameter(Mandatory = $false)]
    [string]$DefaultLanguage = "1033",

    [Parameter(Mandatory = $false)]
    [string]$UsageLocation = "DE",

    [Parameter(Mandatory = $false)]
    [switch]$SkipRedirectUris
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "⚠️ $Message" -ForegroundColor Yellow
}

function Write-Failure {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

# Invoke the Azure CLI and fail hard on a non-zero exit code. Native 'az' errors are never
# treated as success. Output is returned to the caller; secret-bearing output is discarded by
# callers rather than printed.
function Invoke-Az {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $false)][string]$ErrorMessage = "Azure CLI command failed."
    )
    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Failure $ErrorMessage
        if ($output) { Write-Host ($output | Out-String) -ForegroundColor Red }
        exit 1
    }
    return $output
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Preflight — CLI, version and authentication
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Checking environment and Azure authentication"

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Failure "PowerShell 5.1 or newer is required. Current: $($PSVersionTable.PSVersion)"
    exit 1
}
Write-Success "PowerShell $($PSVersionTable.PSVersion)"

if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    Write-Failure "Azure CLI ('az') is not installed or not in PATH."
    Write-Host "Install from https://aka.ms/installazurecliwindows or run: winget install Microsoft.AzureCLI" -ForegroundColor Yellow
    exit 1
}

try {
    $azVersionJson = az version --output json 2>$null | ConvertFrom-Json
    [version]$cliVersion = $azVersionJson.'azure-cli'
    if ($cliVersion -lt [version]"2.60.0") {
        Write-Failure "Azure CLI $($azVersionJson.'azure-cli') is older than the required 2.60.0. Run: az upgrade"
        exit 1
    }
    Write-Success "Azure CLI $($azVersionJson.'azure-cli') (>= 2.60.0)"
} catch {
    Write-WarningMsg "Could not parse 'az version'. Proceeding, but ensure az >= 2.60."
}

$account = $null
try { $account = az account show --output json 2>$null | ConvertFrom-Json } catch { $account = $null }
if (-not $account) {
    Write-Failure "Not logged in to Azure. Run 'az login' (and 'az account set --subscription <id>') first."
    exit 1
}
Write-Success "Azure subscription: $($account.name) ($($account.id))"

if ($account.tenantId -ne $OperatorTenantId) {
    Write-WarningMsg "Signed-in tenant '$($account.tenantId)' differs from -OperatorTenantId '$OperatorTenantId'."
    Write-Host "  This is expected when your Azure subscription lives in a different tenant than the operator sign-in tenant." -ForegroundColor Gray
    Write-Host "  OPERATOR_TENANT_ID will be set to the value you supplied: $OperatorTenantId" -ForegroundColor Gray
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Discover deployment outputs
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Discovering deployment outputs"

if (-not $ContainerAppName -or -not $CosmosAccountName -or -not $Fqdn) {
    $outputsRaw = Invoke-Az -Arguments @(
        "deployment", "group", "show",
        "--resource-group", $ResourceGroup,
        "--name", $DeploymentName,
        "--query", "properties.outputs",
        "--output", "json"
    ) -ErrorMessage "Could not read deployment '$DeploymentName' outputs in resource group '$ResourceGroup'. Pass -ContainerAppName, -CosmosAccountName and -Fqdn explicitly, or -DeploymentName."
    $outputs = $outputsRaw | ConvertFrom-Json

    if (-not $ContainerAppName -and $outputs.containerAppName) { $ContainerAppName = $outputs.containerAppName.value }
    if (-not $CosmosAccountName -and $outputs.cosmosAccountName) { $CosmosAccountName = $outputs.cosmosAccountName.value }
    if (-not $Fqdn -and $outputs.appUrl) { $Fqdn = ($outputs.appUrl.value -replace '^https?://', '') }
}

if (-not $ContainerAppName) { Write-Failure "Container App name not resolved. Pass -ContainerAppName."; exit 1 }
if (-not $CosmosAccountName) { Write-Failure "Cosmos account name not resolved. Pass -CosmosAccountName."; exit 1 }
if (-not $Fqdn) { Write-Failure "Container App FQDN not resolved. Pass -Fqdn."; exit 1 }

Write-Success "Container App:  $ContainerAppName"
Write-Success "Cosmos account: $CosmosAccountName"
Write-Success "FQDN:           $Fqdn"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Collect secrets (never echoed, never written to disk)
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Collecting secrets"

if (-not $ClientSecret) {
    $ClientSecret = Read-Host -Prompt "App registration client secret" -AsSecureString
}
$clientSecretPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret))
if ([string]::IsNullOrWhiteSpace($clientSecretPlain)) {
    Write-Failure "Client secret is empty."
    exit 1
}

# Retrieve the Cosmos primary key. The application authenticates to Cosmos DB with this account
# key (COSMOS_KEY); without it every request fails with 'Required Header authorization is missing'.
$cosmosKey = (Invoke-Az -Arguments @(
    "cosmosdb", "keys", "list",
    "--name", $CosmosAccountName,
    "--resource-group", $ResourceGroup,
    "--type", "keys",
    "--query", "primaryMasterKey",
    "--output", "tsv"
) -ErrorMessage "Could not read the Cosmos DB primary key for '$CosmosAccountName'.").Trim()
if ([string]::IsNullOrWhiteSpace($cosmosKey)) {
    Write-Failure "Cosmos primary key came back empty."
    exit 1
}
Write-Success "Retrieved Cosmos primary key"

# Generate random auth secrets locally.
function New-RandomSecret {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return [Convert]::ToBase64String($bytes)
}
$nextAuthSecret = New-RandomSecret
$authSecret = New-RandomSecret
Write-Success "Generated NextAuth and Auth secrets"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Store secrets on the Container App
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Storing Container App secrets"

Invoke-Az -Arguments @(
    "containerapp", "secret", "set",
    "-n", $ContainerAppName, "-g", $ResourceGroup,
    "--secrets",
    "cosmos-key=$cosmosKey",
    "ad-client-secret=$clientSecretPlain",
    "nextauth-secret=$nextAuthSecret",
    "auth-secret=$authSecret"
) -ErrorMessage "Failed to set Container App secrets." | Out-Null
Write-Success "Secrets stored (cosmos-key, ad-client-secret, nextauth-secret, auth-secret)"

# ─────────────────────────────────────────────────────────────────────────────
# 5. Non-secret environment variables
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Setting non-secret environment variables"

Invoke-Az -Arguments @(
    "containerapp", "update",
    "-n", $ContainerAppName, "-g", $ResourceGroup,
    "--set-env-vars",
    "AZURE_AD_CLIENT_ID=$ClientId",
    "OPERATOR_TENANT_ID=$OperatorTenantId",
    "NEXTAUTH_URL=https://$Fqdn",
    "MAIL_SENDER_UPN=$MailSenderUpn",
    "TENANT_MASTER_ADMIN_EMAILS=$MasterAdminEmails",
    "PP_DEFAULT_CURRENCY=$DefaultCurrency",
    "PP_DEFAULT_LANGUAGE=$DefaultLanguage",
    "USAGE_LOCATION=$UsageLocation"
) -ErrorMessage "Failed to set environment variables." | Out-Null
Write-Success "Environment variables set (admin allow-list included)"

# ─────────────────────────────────────────────────────────────────────────────
# 6. Wire secrets into environment variables (COSMOS_KEY included)
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Wiring secret references"

Invoke-Az -Arguments @(
    "containerapp", "update",
    "-n", $ContainerAppName, "-g", $ResourceGroup,
    "--set-env-vars",
    "COSMOS_KEY=secretref:cosmos-key",
    "AZURE_AD_CLIENT_SECRET=secretref:ad-client-secret",
    "NEXTAUTH_SECRET=secretref:nextauth-secret",
    "AUTH_SECRET=secretref:auth-secret"
) -ErrorMessage "Failed to wire secret references." | Out-Null
Write-Success "Secret references wired (COSMOS_KEY, AZURE_AD_CLIENT_SECRET, NEXTAUTH_SECRET, AUTH_SECRET)"

# ─────────────────────────────────────────────────────────────────────────────
# 7. Switch ingress and image from the bootstrap placeholder to the application
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Switching ingress to port 3000 and deploying the application image"

Invoke-Az -Arguments @(
    "containerapp", "ingress", "update",
    "-n", $ContainerAppName, "-g", $ResourceGroup,
    "--target-port", "3000"
) -ErrorMessage "Failed to switch ingress to port 3000." | Out-Null
Write-Success "Ingress now targets port 3000"

Invoke-Az -Arguments @(
    "containerapp", "update",
    "-n", $ContainerAppName, "-g", $ResourceGroup,
    "--image", $Image
) -ErrorMessage "Failed to switch to the application image '$Image'." | Out-Null
Write-Success "Application image deployed: $Image"

# ─────────────────────────────────────────────────────────────────────────────
# 8. App-registration redirect URIs
# ─────────────────────────────────────────────────────────────────────────────
if (-not $SkipRedirectUris) {
    Write-Step "Adding app-registration redirect URIs"
    Invoke-Az -Arguments @(
        "ad", "app", "update", "--id", $ClientId,
        "--web-redirect-uris",
        "https://$Fqdn/api/auth/callback/microsoft-entra-id",
        "https://$Fqdn/api/auth/onboard-callback",
        "https://$Fqdn/api/auth/adminconsent-callback",
        "https://$Fqdn/api/auth/callback/tenant-maker"
    ) -ErrorMessage "Failed to update redirect URIs. You may lack rights on the app registration; add them manually." | Out-Null
    Write-Success "Redirect URIs set for https://$Fqdn"
} else {
    Write-WarningMsg "Skipped redirect URI update (-SkipRedirectUris)."
}

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "CONFIGURATION COMPLETE"
Write-Host "The application is now configured and serving on port 3000." -ForegroundColor Green
Write-Host ""
Write-Host "  Admin Portal sign-in: https://$Fqdn/sign-in" -ForegroundColor White
Write-Host "  Admin dashboard:      https://$Fqdn/admin" -ForegroundColor White
Write-Host "  Participant redeem:   https://$Fqdn/redeem" -ForegroundColor White
Write-Host ""
Write-Host "A healthy revision does not prove database access — sign in at /sign-in and open /admin" -ForegroundColor Yellow
Write-Host "to confirm Cosmos connectivity. Allow a minute for the new revision to become ready." -ForegroundColor Yellow
