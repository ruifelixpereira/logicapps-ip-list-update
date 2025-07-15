param logicAppName string
param location string = resourceGroup().location

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowDefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {}
          }
        }
      }
      actions: {
        Response: {
          type: 'Response'
          inputs: {
            statusCode: 200
            body: {
              message: 'Hello from Logic App!'
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {}
  }
}
