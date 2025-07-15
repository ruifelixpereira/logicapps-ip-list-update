import os
import logging
import json
import datetime
from azure.identity import ClientSecretCredential
from azure.mgmt.logic import LogicManagementClient
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.resourcegraph import ResourceGraphClient
from azure.mgmt.resourcegraph.models import QueryRequest
import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

#
# On a Timer trigger, this function queries Azure Resource Graph for Logic Apps for which the allowed IP address list needs to be updated.
# For each Logic App a new message is sent to a queue where worker functions subscribe and process it.
#
@app.schedule(schedule="0 2 * * *", arg_name="mytimer", run_on_startup=False, use_monitor=True)
@app.queue_output(arg_name="outputqueue",
                  queue_name="logicapps-to-update",
                  connection="AzureWebJobsStorage")
def get_logic_apps_to_update(mytimer: func.TimerRequest, outputqueue: func.Out[str]) -> None:
    logging.info("Scheduled function 'get_logic_apps_to_update' triggered at %s", datetime.datetime.now())

    tag_key = "update-allowed-ip-ranges"   # <-- Change this to your tag key
    tag_value = "automatic"                # <-- Change this to your tag value

    tenant_id = os.environ.get("AZURE_TENANT_ID")
    client_id = os.environ.get("AZURE_CLIENT_ID")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET")

    try:
        credential = ClientSecretCredential(tenant_id, client_id, client_secret)
        resource_graph_client = ResourceGraphClient(credential)

        query = f"""
        resources
        | where type == 'microsoft.logic/workflows'
        | where tags['{tag_key}'] == '{tag_value}'
        | project name, location, resourceGroup, subscriptionId, tags
        """

        request = QueryRequest(query=query)

        result = resource_graph_client.resources(request)
        #for row in result.data:
        #    logging.info(f"Logic App: {row['name']} (location: {row['location']}, resourceGroup: {row['resourceGroup']})")

        logging.info(f"Total Logic Apps with tag {tag_key}={tag_value}: {len(result.data)}")
        
        # Each item in the returned list will be sent as a separate message to the queue

        # Set all messages at once
        outputqueue.set([json.dumps(row) for row in result.data])

    except Exception as e:
        logging.error(f"Failed to query Logic Apps by tag using Resource Graph: {e}")


#
# Receives a msg containing a Logic App and updates the allowed IP address list.
#
@app.queue_trigger(arg_name="msg",
                   queue_name="logicapps-to-update",
                   connection="AzureWebJobsStorage")
def update_logic_app(msg: func.QueueMessage) -> None:
    logging.info("Processing queue message to update Logic App IP access list.")

    # Check input queue message
    try:
        msg_body = msg.get_body().decode("utf-8")
        data = json.loads(msg_body)

        location = data.get("location")
        if not location:
            logging.error("Missing 'location' in queue message.")
            return
        
        subscription_id = data.get("subscriptionId")
        if not subscription_id:
            logging.error("Missing 'subscriptionId' in queue message.")
            return

        resource_group = data.get("resourceGroup")
        if not resource_group:
            logging.error("Missing 'resourceGroup' in queue message.")
            return

        logic_app_name = data.get("name")
        if not logic_app_name:
            logging.error("Missing 'logic app name' in queue message.")
            return

    except Exception as e:
        logging.error(f"Invalid queue message body: {e}")
        return

    # Get environment variables for authentication
    tenant_id = os.environ.get("AZURE_TENANT_ID")
    client_id = os.environ.get("AZURE_CLIENT_ID")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET")

    # Get the new IP address ranges for the location
    new_ip_ranges = get_new_azure_ip_ranges(location, subscription_id)

    if not new_ip_ranges:
        logging.warning(f"No IP ranges found for location {location}. Skipping Logic App update.")
        return

    try:
        credential = ClientSecretCredential(tenant_id, client_id, client_secret)
        client = LogicManagementClient(credential, subscription_id)

        workflow = client.workflows.get(resource_group, logic_app_name)

        wf_dict = workflow.as_dict() if hasattr(workflow, "as_dict") else dict(workflow)
        access_control = wf_dict.get("access_control", {})

        triggers = access_control.get("triggers", {})
        triggers_allow_list = triggers.get("allowed_caller_ip_addresses", [])

        actions = access_control.get("actions", {})
        actions_allow_list = actions.get("allowed_caller_ip_addresses", [])

        # Add all new IP ranges, avoiding duplicates
        for ip in new_ip_ranges:
            ip_entry = {"address_range": ip}
            if ip_entry not in triggers_allow_list:
                triggers_allow_list.append(ip_entry)
            if ip_entry not in actions_allow_list:
                actions_allow_list.append(ip_entry)

        triggers["allowed_caller_ip_addresses"] = triggers_allow_list
        actions["allowed_caller_ip_addresses"] = actions_allow_list
        access_control["triggers"] = triggers
        access_control["actions"] = actions
        wf_dict["access_control"] = access_control

        updated_workflow = {
            "access_control": wf_dict["access_control"],
            "location": workflow.location,
            "definition": workflow.definition,
            "tags": workflow.tags,
            "parameters": workflow.parameters
        }

        client.workflows.create_or_update(resource_group, logic_app_name, updated_workflow)
        logging.info(f"New IP ranges added to Logic App access list via queue trigger.")

    except Exception as e:
        logging.error(f"Failed to update Logic App from queue trigger: {e}")


#
# Returns a list of IPv4 address ranges for the given Azure region and subscription.
#
def get_new_azure_ip_ranges(location: str, subscription_id: str) -> list:

    tenant_id = os.environ.get("AZURE_TENANT_ID")
    client_id = os.environ.get("AZURE_CLIENT_ID")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET")

    try:
        credential = ClientSecretCredential(tenant_id, client_id, client_secret)
        network_client = NetworkManagementClient(credential, subscription_id)
        response = network_client.service_tags.list(location)

        ip_ranges = []
        for tag in response.values:
            if 'dynamics' in tag.name.lower():
                for prefix in tag.properties.address_prefixes:
                    if ':' not in prefix:  # Only include IPv4 addresses
                        ip_ranges.append(prefix)
        logging.info(f"Found {len(ip_ranges)} IPv4 ranges for region {location}.")
        return ip_ranges

    except Exception as e:
        logging.error(f"Failed to fetch Azure IP ranges for {location}: {e}")
        return []
