#!/bin/bash

# load environment variables
set -a && source .env && set +a

# Required variables
required_vars=(
    "resourceGroupName"
    "location"
    "logicAppNameForTesting"
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

# Variables
BICEP_FILE="logicapp.bicep"

# Get Subscription Id
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

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
# Deploy first Logic App
#
original_logicAppNameForTesting=$logicAppNameForTesting
logicAppNameForTesting="${original_logicAppNameForTesting}01"

# Deploy Logic App using Bicep
az deployment group create \
  --resource-group $resourceGroupName \
  --template-file $BICEP_FILE \
  --parameters logicAppName=$logicAppNameForTesting

# Get callback URL
CALLBACK_URL=$(az rest --method POST \
  --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$resourceGroupName/providers/Microsoft.Logic/workflows/$logicAppNameForTesting/triggers/manual/listCallbackUrl?api-version=2016-06-01" \
  --query "value" \
  --output tsv)

echo "Logic App HTTP Trigger URL:"
echo $CALLBACK_URL

echo "You can test it with: curl -X POST \"$CALLBACK_URL\" \
  -H \"Content-Type: application/json\" \
  -d '{\"message\": \"Hello from curl!\"}'
"

#
# Deploy second Logic App
#
logicAppNameForTesting="${original_logicAppNameForTesting}02"

# Deploy Logic App using Bicep
az deployment group create \
  --resource-group $resourceGroupName \
  --template-file $BICEP_FILE \
  --parameters logicAppName=$logicAppNameForTesting

# Get callback URL
CALLBACK_URL=$(az rest --method POST \
  --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$resourceGroupName/providers/Microsoft.Logic/workflows/$logicAppNameForTesting/triggers/manual/listCallbackUrl?api-version=2016-06-01" \
  --query "value" \
  --output tsv)

echo "Logic App HTTP Trigger URL:"
echo $CALLBACK_URL

echo "You can test it with: curl -X POST \"$CALLBACK_URL\" \
  -H \"Content-Type: application/json\" \
  -d '{\"message\": \"Hello from curl!\"}'
"
