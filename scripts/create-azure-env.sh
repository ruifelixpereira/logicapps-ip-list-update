#!/bin/bash

# load environment variables
set -a && source .env && set +a

# Required variables
required_vars=(
    "resourceGroupName"
    "location"
    "storageAccountName"
    "funcAppName"
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

#
# Create/Get a resource group.
#
rg_query=$(az group list --query "[?name=='$resourceGroupName']")
if [ "$rg_query" == "[]" ]; then
   echo -e "\nCreating Resource group '$resourceGroupName'"
   az group create --name ${resourceGroupName} --location ${location}
else
   echo "Resource group $resourceGroupName already exists."
   #RG_ID=$(az group show --name $resource_group --query id -o tsv)
fi

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

#
# Create Function App
#
fa_query=$(az functionapp list --resource-group $resourceGroupName --query "[?name=='$funcAppName']")
if [ "$fa_query" == "[]" ]; then
    echo -e "\nCreating Function app '$funcAppName'"
    az functionapp create \
        --consumption-plan-location $location \
        --name $funcAppName \
        --os-type Linux \
        --resource-group $resourceGroupName \
        --runtime python \
        --functions-version 4 \
        --runtime-version 3.12 \
        --storage-account $storageAccountName \
        --assign-identity
else
    echo "Function app '$funcAppName' already exists."
fi

#
# Add permissions to the Function App assigned identity
#
FUNCAPP_ID=$(az functionapp identity show --name $funcAppName --resource-group $resourceGroupName --query principalId -o tsv)

# Assign Storage Blob and Queue roles to Function App assigned identity on Storage Account
STORAGE_ACCOUNT_ID=$(az storage account show --name $storageAccountName --resource-group $resourceGroupName --query id -o tsv)
az role assignment create --assignee $FUNCAPP_ID --role "Storage Blob Data Owner" --scope $STORAGE_ACCOUNT_ID
az role assignment create --assignee $FUNCAPP_ID --role "Storage Queue Data Contributor" --scope $STORAGE_ACCOUNT_ID

#
# Create Storage Queues
#
az storage queue create --name "logicapps-to-update" --account-name $storageAccountName

#
# Add default application settings to Function App
#
az functionapp config appsettings set --name $funcAppName --resource-group $resourceGroupName --settings \
    ALLOWED_IP_RANGES_UPDATE_TYPE="merge"

#
# Grant additional permissions to the Function App assigned identity
#

# Get the resource group ID
RG_ID=$(az group show --name "$resourceGroupName" --query id -o tsv)

# Grant Contributor on the resource group
az role assignment create --assignee $FUNCAPP_ID --role "Contributor" --scope ${RG_ID}
