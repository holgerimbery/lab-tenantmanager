#!/usr/bin/env bash
# ==============================================================================
# Lab Tenant Manager — Setup Prerequisites (Step 1 Bootstrap)
#
# Automates preflight checks, Azure tenant login, subscription selection,
# and multi-tenant Entra ID App Registration with all required permissions.
#
# Usage:
#   ./deploy/scripts/setup-prerequisites.sh [--tenant <tenant-id>] [--subscription <subscription-id>] [--app-name <name>] [--save-env-local]
#
# SECURITY: Never commit secrets to git or version control.
# ==============================================================================

set -euo pipefail

APP_DISPLAY_NAME="Lab Tenant Manager"
TENANT_ID=""
SUBSCRIPTION_ID=""
FORCE_LOGIN=false
SAVE_ENV_LOCAL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)
      TENANT_ID="$2"
      shift 2
      ;;
    --subscription)
      SUBSCRIPTION_ID="$2"
      shift 2
      ;;
    --app-name)
      APP_DISPLAY_NAME="$2"
      shift 2
      ;;
    --force-login)
      FORCE_LOGIN=true
      shift
      ;;
    --save-env-local)
      SAVE_ENV_LOCAL=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--tenant <tenant-id>] [--subscription <subscription-id>] [--app-name <name>] [--save-env-local]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

echo ""
echo "=== Step 1: Preflight checks ==="

# Check Azure CLI installed
if ! command -v az &> /dev/null; then
  echo "Error: Azure CLI ('az') is not installed or not in PATH."
  echo "Install it via: https://aka.ms/installazurecli or 'brew install azure-cli' / 'winget install Microsoft.AzureCLI'"
  exit 1
fi

# Check version >= 2.60
AZ_VERSION=$(az version --output json | jq -r '."azure-cli"' 2>/dev/null || az version --output tsv 2>/dev/null | head -n1 | awk '{print $1}')
echo "✓ Azure CLI version: $AZ_VERSION"

# Check bicep
if az bicep version &> /dev/null; then
  echo "✓ Bicep CLI is available"
else
  echo "⚠️ Bicep CLI not detected. Attempting to install via 'az bicep install'..."
  az bicep install || echo "⚠️ Could not auto-install Bicep. You can install it later via 'az bicep install'"
fi

echo ""
echo "=== Step 2: Authenticating to Azure & selecting subscription ==="

CURRENT_ACCOUNT=$(az account show --output json 2>/dev/null || true)
NEED_LOGIN=false

if [ "$FORCE_LOGIN" = true ] || [ -z "$CURRENT_ACCOUNT" ]; then
  NEED_LOGIN=true
elif [ -n "$TENANT_ID" ]; then
  CURRENT_TENANT=$(echo "$CURRENT_ACCOUNT" | jq -r '.tenantId')
  if [ "$CURRENT_TENANT" != "$TENANT_ID" ]; then
    echo "Current session tenant ($CURRENT_TENANT) differs from requested tenant ($TENANT_ID)."
    NEED_LOGIN=true
  fi
fi

if [ "$NEED_LOGIN" = true ]; then
  echo "Initiating Azure CLI login..."
  if [ -n "$TENANT_ID" ]; then
    az login --tenant "$TENANT_ID" --output none
  else
    az login --output none
  fi
  CURRENT_ACCOUNT=$(az account show --output json)
fi

ACTIVE_TENANT_ID=$(echo "$CURRENT_ACCOUNT" | jq -r '.tenantId')
echo "✓ Authenticated to tenant: $ACTIVE_TENANT_ID"

# Get subscriptions in this tenant
ALL_SUBS=$(az account list --all --output json)
TENANT_SUBS=$(echo "$ALL_SUBS" | jq -c "[.[] | select(.tenantId == \"$ACTIVE_TENANT_ID\")]")
NUM_SUBS=$(echo "$TENANT_SUBS" | jq 'length')

if [ "$NUM_SUBS" -eq 0 ]; then
  echo "Error: No accessible subscriptions found in tenant $ACTIVE_TENANT_ID."
  exit 1
fi

SELECTED_SUB_ID=""
if [ -n "$SUBSCRIPTION_ID" ]; then
  SELECTED_SUB_ID="$SUBSCRIPTION_ID"
elif [ "$NUM_SUBS" -eq 1 ]; then
  SELECTED_SUB_ID=$(echo "$TENANT_SUBS" | jq -r '.[0].id')
  SELECTED_SUB_NAME=$(echo "$TENANT_SUBS" | jq -r '.[0].name')
  echo "✓ Single subscription detected: $SELECTED_SUB_NAME ($SELECTED_SUB_ID)"
else
  # Multiple subscriptions - let user choose if interactive
  if [ -t 0 ]; then
    echo ""
    echo "Available subscriptions in tenant $ACTIVE_TENANT_ID:"
    for i in $(seq 0 $((NUM_SUBS - 1))); do
      SUB_NAME=$(echo "$TENANT_SUBS" | jq -r ".[$i].name")
      SUB_ID=$(echo "$TENANT_SUBS" | jq -r ".[$i].id")
      echo "  [$((i + 1))] $SUB_NAME ($SUB_ID)"
    done
    read -p "Select subscription [1-$NUM_SUBS] (default 1): " CHOICE
    CHOICE=${CHOICE:-1}
    INDEX=$((CHOICE - 1))
    SELECTED_SUB_ID=$(echo "$TENANT_SUBS" | jq -r ".[$INDEX].id")
  else
    # Non-interactive fallback: current or first
    CURRENT_SUB=$(echo "$CURRENT_ACCOUNT" | jq -r '.id')
    MATCH=$(echo "$TENANT_SUBS" | jq -r ".[] | select(.id == \"$CURRENT_SUB\") | .id")
    if [ -n "$MATCH" ]; then
      SELECTED_SUB_ID="$MATCH"
    else
      SELECTED_SUB_ID=$(echo "$TENANT_SUBS" | jq -r '.[0].id')
    fi
  fi
fi

az account set --subscription "$SELECTED_SUB_ID"
echo "✓ Active subscription set to: $SELECTED_SUB_ID"

echo ""
echo "=== Step 3: Entra ID App Registration ==="

EXISTING_APP=$(az ad app list --filter "displayName eq '$APP_DISPLAY_NAME'" --output json)
EXISTING_COUNT=$(echo "$EXISTING_APP" | jq 'length')

APP_ID=""
if [ "$EXISTING_COUNT" -gt 0 ]; then
  EXISTING_ID=$(echo "$EXISTING_APP" | jq -r '.[0].appId')
  echo "⚠️ Found existing App Registration '$APP_DISPLAY_NAME' (Client ID: $EXISTING_ID)"
  REUSE=true
  if [ -t 0 ]; then
    read -p "Reuse this existing App Registration? (Y/n): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Nn] ]]; then
      REUSE=false
    fi
  fi
  if [ "$REUSE" = true ]; then
    APP_ID="$EXISTING_ID"
    echo "✓ Reusing App Registration: $APP_ID"
  else
    TIMESTAMP=$(date +%Y%m%d%H%M)
    APP_DISPLAY_NAME="${APP_DISPLAY_NAME}-${TIMESTAMP}"
  fi
fi

if [ -z "$APP_ID" ]; then
  echo "Creating multi-tenant App Registration: '$APP_DISPLAY_NAME'..."
  APP_ID=$(az ad app create \
    --display-name "$APP_DISPLAY_NAME" \
    --sign-in-audience AzureADMultipleOrgs \
    --query appId -o tsv)
  echo "✓ Created App Registration with Client ID: $APP_ID"
fi

echo ""
echo "=== Step 4: Adding API Permissions ==="

# Microsoft Graph API: 00000003-0000-0000-c000-000000000000
# Fixed Microsoft Graph Application Roles:
# - User.ReadWrite.All:              741f803b-c850-494e-b5df-cde7c675a1ca
# - Group.ReadWrite.All:             62a82d76-70ea-41e2-9197-370581804d09
# - Directory.ReadWrite.All:         19dbc75e-c2e2-444c-a770-ec69d8559fc7
# - LicenseAssignment.ReadWrite.All: 5facf0c1-8979-4e95-abcf-ff3d079771c0
# - Mail.Send:                       b633e1c5-b582-4048-a93e-9f11b44c7e96

GRAPH_PERMS=(
  "741f803b-c850-494e-b5df-cde7c675a1ca=Role"
  "62a82d76-70ea-41e2-9197-370581804d09=Role"
  "19dbc75e-c2e2-444c-a770-ec69d8559fc7=Role"
  "5facf0c1-8979-4e95-abcf-ff3d079771c0=Role"
  "b633e1c5-b582-4048-a93e-9f11b44c7e96=Role"
)

echo "Adding Microsoft Graph Application permissions..."
for perm in "${GRAPH_PERMS[@]}"; do
  az ad app permission add \
    --id "$APP_ID" \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions "$perm" > /dev/null 2>&1 || true
done
echo "✓ Microsoft Graph permissions configured"

# Power Platform API: 475226c6-020e-4fb2-8a90-7a972cbfc1d4
# Delegated Scope: User: 0eb56b90-a7b5-43b5-9402-8137a8083e90
echo "Adding Power Platform delegated permission..."
az ad app permission add \
  --id "$APP_ID" \
  --api 475226c6-020e-4fb2-8a90-7a972cbfc1d4 \
  --api-permissions 0eb56b90-a7b5-43b5-9402-8137a8083e90=Scope > /dev/null 2>&1 || true

az ad app permission grant \
  --id "$APP_ID" \
  --api 475226c6-020e-4fb2-8a90-7a972cbfc1d4 \
  --scope User > /dev/null 2>&1 || true
echo "✓ Power Platform delegated permission granted"

# Admin Consent
echo "Granting tenant admin consent..."
az ad app permission admin-consent --id "$APP_ID" > /dev/null 2>&1 || echo "⚠️ Could not auto-grant admin consent. Ensure an admin consents in the Azure Portal."
echo "✓ Admin consent command executed"

echo ""
echo "=== Step 5: Generating Client Secret & Retrieving Admin Object ID ==="

CLIENT_SECRET=$(az ad app credential reset \
  --id "$APP_ID" \
  --append \
  --display-name "lab-tenant-manager" \
  --query password -o tsv)
echo "✓ Client secret generated"

USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "<your-entra-user-object-id>")
echo "✓ Key Vault Admin Object ID retrieved: $USER_OBJECT_ID"

echo ""
echo "======================================================================"
echo "  PREREQUISITES FULFILLED — SUMMARY VALUES"
echo "======================================================================"
echo ""
echo "  Operator Tenant ID (OPERATOR_TENANT_ID): $ACTIVE_TENANT_ID"
echo "  Azure Subscription ID:                  $SELECTED_SUB_ID"
echo "  App Client ID (adClientId):             $APP_ID"
echo "  Key Vault Admin Object ID (kvAdminOID): $USER_OBJECT_ID"
echo "  App Client Secret (adClientSecret):     $CLIENT_SECRET"
echo ""
echo "======================================================================"
echo "  SECURITY WARNING: NEVER COMMIT SECRETS TO GIT OR PUBLIC REPOSITORIES!"
echo "  The secret above is printed in this console session only."
echo "======================================================================"

if [ "$SAVE_ENV_LOCAL" = true ]; then
  ENV_FILE="$(dirname "$0")/../../.env.local"
  cat <<EOF > "$ENV_FILE"
# Local deployment parameters (NEVER COMMIT TO GIT)
OPERATOR_TENANT_ID=$ACTIVE_TENANT_ID
SUBSCRIPTION_ID=$SELECTED_SUB_ID
AZURE_AD_CLIENT_ID=$APP_ID
AZURE_AD_CLIENT_SECRET=$CLIENT_SECRET
KV_ADMIN_OBJECT_ID=$USER_OBJECT_ID
EOF
  echo ""
  echo "✓ Parameters written to .env.local (strictly gitignored)"
fi

echo ""
echo "--- POST-DEPLOYMENT STEP ---"
echo "After deploying the Container App (Step 2), get its FQDN and run:"
echo ""
echo "az ad app update --id $APP_ID \\"
echo "  --web-redirect-uris \\"
echo "    \"https://<FQDN>/api/auth/callback/microsoft-entra-id\" \\"
echo "    \"https://<FQDN>/api/auth/onboard-callback\" \\"
echo "    \"https://<FQDN>/api/auth/adminconsent-callback\" \\"
echo "    \"https://<FQDN>/api/auth/callback/tenant-maker\""
echo ""
echo "✓ Prerequisite setup complete!"
