<#
.SYNOPSIS
    Fulfills Step 1 prerequisites for Lab Tenant Manager deployment.

.DESCRIPTION
    Automates preflight checks, Azure tenant login, subscription selection,
    and multi-tenant Entra ID App Registration with all required Microsoft Graph
    and Power Platform permissions.
    Ensures secrets are NEVER committed to version control.

.PARAMETER TenantId
    Optional Azure / Entra ID tenant ID to log into. If omitted, uses current or prompts.

.PARAMETER SubscriptionId
    Optional Azure subscription ID. If omitted, selects automatically or prompts.

.PARAMETER AppDisplayName
    Display name for the Entra ID application registration. Default: "Lab Tenant Manager".

.PARAMETER ForceLogin
    Forces a fresh `az login` even if already authenticated.

.PARAMETER SaveEnvLocal
    Optionally writes the output values to a gitignored .env.local file.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$AppDisplayName = "Lab Tenant Manager",

    [Parameter(Mandatory = $false)]
    [switch]$ForceLogin,

    [Parameter(Mandatory = $false)]
    [switch]$SaveEnvLocal
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

# ─────────────────────────────────────────────────────────────────────────────
# 1. Environment & Tool Preflight Verification
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Checking environment prerequisites and CLI tools"

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Failure "PowerShell 5.1 or newer is required. Current: $($PSVersionTable.PSVersion)"
    exit 1
}
Write-Success "PowerShell $($PSVersionTable.PSVersion)"

# Check Azure CLI installation
$azCmd = Get-Command "az" -ErrorAction SilentlyContinue
if (-not $azCmd) {
    Write-Failure "Azure CLI ('az') is not installed or not in PATH."
    Write-Host "Install Azure CLI from: https://aka.ms/installazurecliwindows or run: winget install Microsoft.AzureCLI" -ForegroundColor Yellow
    exit 1
}

# Check Azure CLI version >= 2.60
try {
    $azVersionJson = az version --output json 2>$null | ConvertFrom-Json
    $cliVersionStr = $azVersionJson.'azure-cli'
    [version]$cliVersion = $cliVersionStr
    if ($cliVersion -lt [version]"2.60.0") {
        Write-Failure "Azure CLI version $cliVersionStr is older than required 2.60.0."
        Write-Host "Update Azure CLI by running: az upgrade" -ForegroundColor Yellow
        exit 1
    }
    Write-Success "Azure CLI version $cliVersionStr (>= 2.60.0 required)"
} catch {
    Write-WarningMsg "Could not parse 'az version' output. Proceeding, but ensure az >= 2.60."
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Azure Login & Subscription Selection
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Authenticating to Azure & selecting subscription"

$currentAccount = $null
if (-not $ForceLogin) {
    try {
        $currentAccount = az account show --output json 2>$null | ConvertFrom-Json
    } catch {
        $currentAccount = $null
    }
}

$needLogin = $false
if ($ForceLogin -or (-not $currentAccount)) {
    $needLogin = $true
} elseif ($TenantId -and ($currentAccount.tenantId -ne $TenantId)) {
    Write-Host "Current session is logged into tenant '$($currentAccount.tenantId)', but requested tenant is '$TenantId'." -ForegroundColor Yellow
    $needLogin = $true
}

if ($needLogin) {
    Write-Host "Initiating Azure CLI login..." -ForegroundColor Yellow
    if ($TenantId) {
        az login --tenant $TenantId --output none
    } else {
        az login --output none
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Failure "Azure CLI login failed."
        exit 1
    }
    $currentAccount = az account show --output json | ConvertFrom-Json
}

$activeTenantId = $currentAccount.tenantId
Write-Success "Authenticated to tenant: $activeTenantId"
if ($currentAccount.user -and $currentAccount.user.name) {
    Write-Host "  Signed-in user: $($currentAccount.user.name)" -ForegroundColor Gray
}

# Retrieve subscriptions for active tenant
$allSubscriptions = az account list --all --output json | ConvertFrom-Json
$tenantSubscriptions = @($allSubscriptions | Where-Object { $_.tenantId -eq $activeTenantId -and $_.state -eq 'Enabled' })

if ($tenantSubscriptions.Count -eq 0) {
    $tenantSubscriptions = @($allSubscriptions | Where-Object { $_.tenantId -eq $activeTenantId })
}

if ($tenantSubscriptions.Count -eq 0) {
    Write-Failure "No accessible subscriptions found in tenant '$activeTenantId'."
    exit 1
}

$selectedSub = $null
if ($SubscriptionId) {
    $selectedSub = $tenantSubscriptions | Where-Object { $_.id -eq $SubscriptionId }
    if (-not $selectedSub) {
        Write-Failure "Subscription ID '$SubscriptionId' was not found in tenant '$activeTenantId'."
        exit 1
    }
} elseif ($tenantSubscriptions.Count -eq 1) {
    $selectedSub = $tenantSubscriptions[0]
    Write-Success "Single subscription detected: $($selectedSub.name) ($($selectedSub.id))"
} else {
    # Check if current subscription in account context is in this tenant
    $currentSubInTenant = $tenantSubscriptions | Where-Object { $_.id -eq $currentAccount.id }
    
    # Interactive selection if possible
    if ([Environment]::UserInteractive) {
        Write-Host "`nAvailable subscriptions in tenant $activeTenantId :" -ForegroundColor Cyan
        for ($i = 0; $i -lt $tenantSubscriptions.Count; $i++) {
            $sub = $tenantSubscriptions[$i]
            $marker = if ($sub.id -eq $currentAccount.id) { " [Current Default]" } else { "" }
            Write-Host "  [$($i + 1)] $($sub.name) ($($sub.id))$marker"
        }
        
        $choiceIndex = -1
        while ($choiceIndex -lt 0 -or $choiceIndex -ge $tenantSubscriptions.Count) {
            $defaultChoice = if ($currentSubInTenant) { ($tenantSubscriptions.IndexOf($currentSubInTenant) + 1) } else { 1 }
            $promptText = "Select subscription [1-$($tenantSubscriptions.Count)] (default $defaultChoice): "
            $inputVal = Read-Host -Prompt $promptText
            if ([string]::IsNullOrWhiteSpace($inputVal)) {
                $choiceIndex = $defaultChoice - 1
            } else {
                $parsed = 0
                if ([int]::TryParse($inputVal, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le $tenantSubscriptions.Count) {
                    $choiceIndex = $parsed - 1
                } else {
                    Write-Host "Invalid choice. Please enter a number between 1 and $($tenantSubscriptions.Count)." -ForegroundColor Yellow
                }
            }
        }
        $selectedSub = $tenantSubscriptions[$choiceIndex]
    } else {
        # Non-interactive fallback
        if ($currentSubInTenant) {
            $selectedSub = $currentSubInTenant
        } else {
            $selectedSub = $tenantSubscriptions[0]
        }
    }
}

az account set --subscription $selectedSub.id
if ($LASTEXITCODE -ne 0) {
    Write-Failure "Failed to set active subscription to $($selectedSub.id)."
    exit 1
}
Write-Success "Active subscription: $($selectedSub.name) ($($selectedSub.id))"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Multi-Tenant Entra ID App Registration
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Configuring Entra ID App Registration"

$existingApps = az ad app list --filter "displayName eq '$AppDisplayName'" --output json | ConvertFrom-Json
$appId = $null
$reusedApp = $false

if ($existingApps -and $existingApps.Count -gt 0) {
    $existingApp = $existingApps[0]
    Write-WarningMsg "Found existing App Registration '$AppDisplayName' (Client ID: $($existingApp.appId))."
    $reuse = $true
    if ([Environment]::UserInteractive) {
        $confirm = Read-Host "Reuse this existing App Registration? (Y/n)"
        if ($confirm -match "^[Nn]") {
            $reuse = $false
        }
    }
    
    if ($reuse) {
        $appId = $existingApp.appId
        $reusedApp = $true
        Write-Success "Reusing App Registration '$AppDisplayName' (Client ID: $appId)"
    } else {
        $timestamp = (Get-Date).ToString("yyyyMMdd-HHmm")
        $AppDisplayName = "$AppDisplayName-$timestamp"
        Write-Host "Creating new App Registration with name: '$AppDisplayName'..." -ForegroundColor Yellow
    }
}

if (-not $reusedApp) {
    Write-Host "Creating multi-tenant App Registration: '$AppDisplayName'..." -ForegroundColor Yellow
    $createAppResult = az ad app create `
        --display-name "$AppDisplayName" `
        --sign-in-audience AzureADMultipleOrgs `
        --output json | ConvertFrom-Json
    
    $appId = $createAppResult.appId
    Write-Success "Created App Registration with Client ID: $appId"
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. API Permissions (Microsoft Graph & Power Platform)
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Adding required API permissions (Graph App roles & Power Platform delegated)"

# Microsoft Graph API: 00000003-0000-0000-c000-000000000000
# Fixed Microsoft Graph Application Roles:
# - User.ReadWrite.All:              741f803b-c850-494e-b5df-cde7c675a1ca
# - Group.ReadWrite.All:             62a82d76-70ea-41e2-9197-370581804d09
# - Directory.ReadWrite.All:         19dbc75e-c2e2-444c-a770-ec69d8559fc7
# - LicenseAssignment.ReadWrite.All: 5facf0c1-8979-4e95-abcf-ff3d079771c0
# - Mail.Send:                       b633e1c5-b582-4048-a93e-9f11b44c7e96
$graphPermissions = @(
    "741f803b-c850-494e-b5df-cde7c675a1ca=Role",
    "62a82d76-70ea-41e2-9197-370581804d09=Role",
    "19dbc75e-c2e2-444c-a770-ec69d8559fc7=Role",
    "5facf0c1-8979-4e95-abcf-ff3d079771c0=Role",
    "b633e1c5-b582-4048-a93e-9f11b44c7e96=Role"
)

Write-Host "Configuring Microsoft Graph permissions..." -ForegroundColor Yellow
foreach ($perm in $graphPermissions) {
    az ad app permission add `
        --id $appId `
        --api 00000003-0000-0000-c000-000000000000 `
        --api-permissions $perm 2>&1 | Out-Null
}
Write-Success "Microsoft Graph permissions added"

# Power Platform API: 475226c6-020e-4fb2-8a90-7a972cbfc1d4
# Fixed Power Platform Delegated Scope:
# - User: 0eb56b90-a7b5-43b5-9402-8137a8083e90
Write-Host "Configuring Power Platform delegated permissions..." -ForegroundColor Yellow
az ad app permission add `
    --id $appId `
    --api 475226c6-020e-4fb2-8a90-7a972cbfc1d4 `
    --api-permissions 0eb56b90-a7b5-43b5-9402-8137a8083e90=Scope 2>&1 | Out-Null

az ad app permission grant `
    --id $appId `
    --api 475226c6-020e-4fb2-8a90-7a972cbfc1d4 `
    --scope User 2>&1 | Out-Null
Write-Success "Power Platform delegated permission granted"

# Grant Admin Consent for Microsoft Graph Application Permissions
Write-Host "Granting tenant admin consent..." -ForegroundColor Yellow
az ad app permission admin-consent --id $appId 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Success "Admin consent granted"
} else {
    Write-WarningMsg "Could not grant admin consent automatically. Ensure you have Global Administrator or Privileged Role Administrator rights."
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Client Secret & Object ID
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Generating Client Secret & retrieving Key Vault Admin Object ID"

$credentialResult = az ad app credential reset `
    --id $appId `
    --append `
    --display-name "lab-tenant-manager" `
    --output json | ConvertFrom-Json

$clientSecret = $credentialResult.password
Write-Success "Client secret generated successfully"

$userObjectId = az ad signed-in-user show --query id -o tsv 2>$null
if (-not $userObjectId) {
    Write-WarningMsg "Could not resolve current signed-in user Object ID via 'az ad signed-in-user show'."
    $userObjectId = "<your-entra-user-object-id>"
} else {
    Write-Success "Retrieved Key Vault Admin Object ID: $userObjectId"
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Summary Output & Security Notice
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "PREREQUISITES FULFILLED — SUMMARY"

Write-Host "======================================================================" -ForegroundColor Green
Write-Host "  Copy these values into the Azure Portal template / CLI parameters:" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Operator Tenant ID (OPERATOR_TENANT_ID): $activeTenantId" -ForegroundColor White
Write-Host "  Azure Subscription ID:                  $($selectedSub.id)" -ForegroundColor White
Write-Host "  App Client ID (adClientId):             $appId" -ForegroundColor White
Write-Host "  Key Vault Admin Object ID (kvAdminOID): $userObjectId" -ForegroundColor White
Write-Host "  App Client Secret (adClientSecret):     $clientSecret" -ForegroundColor Yellow
Write-Host ""
Write-Host "======================================================================" -ForegroundColor Yellow
Write-Host "  SECURITY NOTICE: NEVER COMMIT SECRETS TO GIT OR PUBLIC REPOSITORIES!" -ForegroundColor Red
Write-Host "  The client secret above is shown in your terminal session only." -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Yellow

# Optional .env.local write if requested
if ($SaveEnvLocal) {
    # Verify .gitignore covers .env.local
    $envLocalPath = Join-Path $PSScriptRoot "..\..\.env.local"
    $envContent = @"
# Local deployment parameters (NEVER COMMIT TO GIT)
OPERATOR_TENANT_ID=$activeTenantId
SUBSCRIPTION_ID=$($selectedSub.id)
AZURE_AD_CLIENT_ID=$appId
AZURE_AD_CLIENT_SECRET=$clientSecret
KV_ADMIN_OBJECT_ID=$userObjectId
"@
    Set-Content -Path $envLocalPath -Value $envContent -Encoding UTF8
    Write-Host "`n✓ Wrote parameters to .env.local (strictly gitignored)" -ForegroundColor Green
}

# Post-Deployment redirect URI instructions
Write-Host "`n--- POST-DEPLOYMENT STEP ---" -ForegroundColor Cyan
Write-Host "After deploying the Container App (Step 2), get its FQDN and run:" -ForegroundColor Cyan
Write-Host ""
Write-Host "az ad app update --id $appId ``" -ForegroundColor White
Write-Host "  --web-redirect-uris ``" -ForegroundColor White
Write-Host "    `"https://<FQDN>/api/auth/callback/microsoft-entra-id`" ``" -ForegroundColor White
Write-Host "    `"https://<FQDN>/api/auth/onboard-callback`" ``" -ForegroundColor White
Write-Host "    `"https://<FQDN>/api/auth/adminconsent-callback`" ``" -ForegroundColor White
Write-Host "    `"https://<FQDN>/api/auth/callback/tenant-maker`"" -ForegroundColor White
Write-Host ""
Write-Host "Setup prerequisites completed successfully!" -ForegroundColor Green
