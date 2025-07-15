#!/bin/bash

# The user/sp running this script needs to have at least the role of "Key Vault Secrets Officer" in the Key Vault

# load environment variables
set -a && source .env && set +a

# Required variables
required_vars=(
    "resourceGroupName"
    "storageAccountName"
    "localDevelopmentAppName"
)

# Set the current directory to where the script lives.
cd "$(dirname "$0")"

# Function to check if all required arguments have been set
check_required_arguments() {
    # Array to store the names of the missing arguments
    local missing_arguments=()

    # Loop through the array of required argument names
    for arg_name in "${required_vars[@]}"; do
        # Check if the argument value is empty
        if [[ -z "${!arg_name}" ]]; then
            # Add the name of the missing argument to the array
            missing_arguments+=("${arg_name}")
        fi
    done

    # Check if any required argument is missing
    if [[ ${#missing_arguments[@]} -gt 0 ]]; then
        echo -e "\nError: Missing required arguments:"
        printf '  %s\n' "${missing_arguments[@]}"
        [ ! \( \( $# == 1 \) -a \( "$1" == "-c" \) \) ] && echo "  Either provide a .env file or all the arguments, but not both at the same time."
        [ ! \( $# == 22 \) ] && echo "  All arguments must be provided."
        echo ""
        exit 1
    fi
}

####################################################################################

# Check if all required arguments have been set
check_required_arguments

####################################################################################

# Get Subscription Id
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

#
# Create Service principal to be used by GitHub Actions in deployments
#
#az ad sp create-for-rbac \
#    --name ${githubDeploymentAppName} \
#    --role contributor \
#    --scopes /subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${resourceGroupName}/providers/Microsoft.Web/sites/${funcAppName} \
#    --sdk-auth

# Variables
#appName="my-app-$(date +%s)"  # Unique app name using timestamp

# Create the application
appId=$(az ad app create \
  --display-name "$localDevelopmentAppName" \
  --query appId -o tsv)

echo "Application created with App ID: $appId"

# Create the service principal
spId=$(az ad sp create --id "$appId" --query id -o tsv)
echo "Service Principal created with Object ID: $spId"

# Generate a client secret (Azure will create it)
secret=$(az ad app credential reset \
  --id "$appId" \
  --append \
  --end-date "$(date -u -d '3 week' +%Y-%m-%dT%H:%M:%SZ)" \
  --query password -o tsv)

# Output credentials
echo "=============================="
echo "App Name: $localDevelopmentAppName"
echo "App ID: $appId"
echo "Service Principal ID: $spId"
echo "Client Secret: $secret"
echo "=============================="

#
# Create storage account
#
sa_query=$(az storage account list --query "[?name=='$storageAccountName']")
if [ "$sa_query" == "[]" ]; then
    echo -e "\nCreating Storage account '$storageAccountName'"
    az storage account create \
        --name $storageAccountName \
        --resource-group ${resourceGroupName} \
        --allow-blob-public-access false \
        --allow-shared-key-access true \
        --kind StorageV2 \
        --sku Standard_LRS
else
    echo "Storage account $storageAccountName already exists."
fi

# Assign Storage Blob and Queue roles to the new app on Storage Account
STORAGE_ACCOUNT_ID=$(az storage account show --name $storageAccountName --resource-group $resourceGroupName --query id -o tsv)
az role assignment create --assignee $spId --role "Storage Blob Data Owner" --scope $STORAGE_ACCOUNT_ID
az role assignment create --assignee $spId --role "Storage Queue Data Contributor" --scope $STORAGE_ACCOUNT_ID

# Create Storage Queues
az storage queue create --name "logicapps-to-update" --account-name $storageAccountName

# Get Storage account connection string
STORAGE_CONNECTION_STRING=$(az storage account show-connection-string --name $storageAccountName --resource-group $resourceGroupName --query connectionString -o tsv)

# Get tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)

#
# Generate example local.settings.json payload
#
cat > local.settings.dev.json <<EOF
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AzureWebJobsStorage": "$STORAGE_CONNECTION_STRING",
    "AZURE_TENANT_ID": "$TENANT_ID",
    "AZURE_CLIENT_ID": "$appId",
    "AZURE_CLIENT_SECRET": "$secret",
    "ALLOWED_IP_RANGES_UPDATE_TYPE": "merge"
  }
}
EOF