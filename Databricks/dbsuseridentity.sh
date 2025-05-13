#!/bin/bash

# === Usage ===
# ./assign-umi-role.sh <subscription-id> <databricks-rg> <databricks-workspace-name> <identity-name> <role> <assignment-scope>

set -e

# === Input Parameters ===
SUBSCRIPTION_ID="$1"
DATABRICKS_RG="$2"
WORKSPACE_NAME="$3"
IDENTITY_NAME="$4" # e.g., dbmanagedidentity
ROLE="Virtual Machine Contributor"
ASSIGNMENT_SCOPE="$6" # e.g., /subscriptions/xxxxx or /subscriptions/xxxxx/resourceGroups/xxxxx

# === Check required parameters ===
if [ $# -ne 6 ]; then
  echo "Usage: $0 <subscription-id> <databricks-rg> <databricks-workspace-name> <identity-name> <role> <assignment-scope>"
  echo "Example: $0 xxxxx-rg myworkspace dbmanagedidentity 'Virtual Machine Contributor' /subscriptions/xxxxx"
  exit 1
fi

# === Set subscription context ===
az account set --subscription "$SUBSCRIPTION_ID"

# === Get the Managed Resource Group (MRG) of the Databricks workspace ===
MRG=$(az databricks workspace show \
    --name "$WORKSPACE_NAME" \
    --resource-group "$DATABRICKS_RG" \
    --query "managedResourceGroupId" \
    --output tsv)

if [ -z "$MRG" ]; then
  echo "❌ Could not retrieve managed resource group for workspace '$WORKSPACE_NAME'"
  exit 1
fi

echo "✔ Managed Resource Group ID: $MRG"

# Extract resource group name from resource ID
MRG_NAME=$(basename "$MRG")

# === Get the user-assigned identity from MRG ===
IDENTITY=$(az identity show \
    --name "$IDENTITY_NAME" \
    --resource-group "$MRG_NAME" \
    --query "{id:id, clientId:clientId, principalId:principalId}" \
    --output json)

if [ -z "$IDENTITY" ]; then
  echo "❌ Identity '$IDENTITY_NAME' not found in managed resource group '$MRG_NAME'"
  exit 1
fi

# === Parse principalId using jq ===
PRINCIPAL_ID=$(echo "$IDENTITY" | jq -r '.principalId')

echo "✔ Identity found. Principal ID: $PRINCIPAL_ID"

# === Assign role to the identity ===
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "$ROLE" \
  --scope "$ASSIGNMENT_SCOPE"

echo "✅ Role '$ROLE' assigned to identity '$IDENTITY_NAME' at scope '$ASSIGNMENT_SCOPE'"