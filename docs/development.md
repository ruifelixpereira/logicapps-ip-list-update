# Development

To run your Azure Function locally using a Python virtual environment (venv), follow these steps:

## 1. Prerequisites
- Python 3.12
- Azure Functions Core Tools
- Azure CLI (optional but useful)


## 2. Steps to Run Locally

✅ Create and activate a virtual environment

```bash
python -m venv .venv
source .venv/bin/activate
```

✅ Install dependencies

```bash
pip install -r requirements.txt
```

✅ Start the Azure Function runtime

Make sure you're in the root of your function app (where `host.json` is located), then run:

```bash
func start
```

This will start your function locally:

```bash
Azure Functions Core Tools
Core Tools Version:       4.0.6821 Commit hash: N/A +c09a2033faa7ecf51b3773308283af0ca9a99f83 (64-bit)
Function Runtime Version: 4.1036.1.23224

[2025-07-15T20:30:53.808Z] Worker process started and initialized.

Functions:

        get_logic_apps_to_update: timerTrigger

        update_logic_app: queueTrigger

For detailed output, run func with --verbose flag.
```

## 3. Test the Function

You can test it using curl or Postman:

```bash
# Test timer trigger locally
curl --request POST -H "Content-Type:application/json" -H "x-functions-key:xxxxxxxxxxxxx" --data '{"input":""}'  http://localhost:7071/admin/functions/get_logic_apps_to_update

# Test HTTP Trigger
curl -X POST http://localhost:7071/api/update-ip \
  -H "Content-Type: application/json" \
  -H "x-functions-key:xxxxxxxxxxxxx==" \
  -d '{"cidr": "203.0.113.42/32"}'
```

## 4. Optional: Set Environment Variables

You can define your Azure credentials and Logic App details in `local.settings.json`, which is automatically loaded when running locally.

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AzureWebJobsSecretStorageType": "files",
    "AZURE_TENANT_ID": "your-tenant-id",
    "AZURE_CLIENT_ID": "your-client-id",
    "AZURE_CLIENT_SECRET": "your-client-secret",
    "ALLOWED_IP_RANGES_UPDATE_TYPE": "reset | merge" // Choose one
  }
}
```
